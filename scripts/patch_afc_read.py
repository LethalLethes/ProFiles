#!/usr/bin/env python3
from pathlib import Path

root = Path("AirCard-iOS/rust-core")
exploit_path = root / "src/exploit.rs"
lib_path = root / "src/lib.rs"
header_path = root / "include/airlift.h"

src = exploit_path.read_text()
old_listing = """                let mut entries = afc
                    .list_dir(&remote_path)
                    .await
                    .map_err(|e| format!("AFC error: {e:?}"))?;

                entries.retain(|name| name != "." && name != "..");
                entries.sort_by_key(|name| name.to_lowercase());

                serde_json::to_string(&entries)
                    .map_err(|e| format!("JSON error: {e}"))"""
new_listing = """                let mut names = afc
                    .list_dir(&remote_path)
                    .await
                    .map_err(|e| format!("AFC error: {e:?}"))?;
                names.retain(|name| name != "." && name != "..");
                names.sort_by_key(|name| name.to_lowercase());

                let mut entries = Vec::new();
                for name in names {
                    let child = if remote_path == "/" {
                        format!("/{}", name)
                    } else {
                        format!("{}/{}", remote_path.trim_end_matches('/'), name)
                    };
                    // Metadata is preferred. If AFC cannot return metadata,
                    // probe the path as a directory so a real folder is not
                    // silently shown as an unreadable file.
                    let is_directory = match afc.get_file_info(&child).await {
                        Ok(info) => info.st_ifmt == "S_IFDIR",
                        Err(_) => afc.list_dir(&child).await.is_ok(),
                    };
                    entries.push(serde_json::json!({
                        "name": name,
                        "isDirectory": is_directory
                    }));
                }
                serde_json::to_string(&entries)
                    .map_err(|e| format!("JSON error: {e}"))"""
if old_listing in src:
    src = src.replace(old_listing, new_listing, 1)
elif "// Metadata is preferred. If AFC cannot return metadata," not in src:
    raise SystemExit("Could not patch AFC directory metadata block")
if "pub unsafe fn afc_read_file(" not in src:
    anchor = "// Public FFI entry point"
    if anchor not in src:
        raise SystemExit("AFC insertion anchor not found in exploit.rs")
    code = r'''
// Read-only access to one regular file exposed by the paired AFC service.
pub unsafe fn afc_read_file(
    pairing_path: *const c_char,
    remote_path: *const c_char,
    out_data: *mut *mut c_char,
    out_len: *mut usize,
    out_error: *mut *mut c_char,
) -> i32 {
    if out_data.is_null() || out_len.is_null() { return 2; }
    let pairing_path = opt_str(pairing_path, "airlift_pairing.plist");
    let remote_path = opt_str(remote_path, "");
    if !remote_path.starts_with('/') || remote_path.split('/').any(|p| p == "." || p == "..") || remote_path.contains('\0') {
        if !out_error.is_null() { *out_error = cstr("Invalid AFC path."); }
        return 1;
    }
    let res = crate::ffi_util::run_with_large_stack("al_afc_read_file", move || {
        idevice_ffi::run_sync_local(async move {
            let pairing_bytes = std::fs::read(&pairing_path).map_err(|e| format!("Pairing file error: {e}"))?;
            let logger = Logger { cb: None, ctx: std::ptr::null_mut() };
            let mut tunnel = connect_tunnel(&pairing_bytes, &logger).await?;
            let mut afc = tunnel.connect_afc(&logger).await?;
            let mut fd = afc.open(&remote_path, AfcFopenMode::RdOnly).await
                .map_err(|e| format!("AFC open error: {e:?}"))?;
            let bytes = fd.read_entire().await.map_err(|e| format!("AFC read error: {e:?}"))?;
            let _ = fd.close().await;
            Ok::<Vec<u8>, String>(bytes)
        })
    });
    match res {
        Ok(Ok(bytes)) => {
            let ptr = libc::malloc(bytes.len().max(1)) as *mut u8;
            if ptr.is_null() {
                if !out_error.is_null() { *out_error = cstr("Out of memory."); }
                return 1;
            }
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
            *out_len = bytes.len();
            *out_data = ptr as *mut c_char;
            0
        }
        Ok(Err(error)) | Err(error) => {
            if !out_error.is_null() { *out_error = cstr(error); }
            1
        }
    }
}
'''
    src = src.replace(anchor, code + "\n" + anchor, 1)
    exploit_path.write_text(src)

lib = lib_path.read_text()
if "al_afc_read_file(" not in lib:
    anchor = "// ---------------------------------------------------------------------------\n// Exploit file operations"
    if anchor not in lib:
        raise SystemExit("AFC FFI insertion anchor not found in lib.rs")
    code = r'''
#[no_mangle]
pub unsafe extern "C" fn al_afc_read_file(
    pairing_path: *const c_char,
    remote_path: *const c_char,
    out_data: *mut *mut c_char,
    out_len: *mut usize,
    out_error: *mut *mut c_char,
) -> i32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        exploit::afc_read_file(pairing_path, remote_path, out_data, out_len, out_error)
    })) {
        Ok(rc) => rc,
        Err(e) => {
            if !out_error.is_null() {
                *out_error = ffi_util::cstr(format!("Rust panic in al_afc_read_file: {e:?}"));
            }
            1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn al_buffer_free(p: *mut c_char) {
    if !p.is_null() { libc::free(p as *mut libc::c_void); }
}
'''
    lib = lib.replace(anchor, code + "\n" + anchor, 1)
    lib_path.write_text(lib)

header = header_path.read_text()
if "al_afc_read_file(" not in header:
    anchor = "// Run the AirTraffic sandbox escape."
    decl = r'''// Read a file from the paired AFC namespace. Release out_data with al_buffer_free.
int32_t al_afc_read_file(const char *pairing_path, const char *remote_path,
                         char **out_data, size_t *out_len, char **out_error);
void al_buffer_free(char *p);

'''
    if anchor not in header:
        raise SystemExit("AFC header insertion anchor not found")
    header = header.replace(anchor, decl + anchor, 1)
    header_path.write_text(header)

print("AFC read-file FFI patch applied.")


# AFC file-manager write and delete APIs (restricted to the paired AFC namespace).
if "pub unsafe fn afc_write_file(" not in src:
    anchor = "// Public FFI entry point"
    code = r"""
pub unsafe fn afc_write_file(pairing_path: *const c_char, remote_path: *const c_char,
    data: *const u8, data_len: usize, out_error: *mut *mut c_char) -> i32 {
    if data.is_null() && data_len > 0 { if !out_error.is_null() { *out_error = cstr("Missing data."); } return 1; }
    let pairing_path = opt_str(pairing_path, "airlift_pairing.plist");
    let remote_path = opt_str(remote_path, "");
    if !remote_path.starts_with('/') || remote_path == "/" || remote_path.split('/').any(|p| p == "." || p == "..") {
        if !out_error.is_null() { *out_error = cstr("Invalid AFC path."); } return 1;
    }
    let bytes = if data_len == 0 { Vec::new() } else { std::slice::from_raw_parts(data, data_len).to_vec() };
    let result = crate::ffi_util::run_with_large_stack("afc_write_file", move || {
        idevice_ffi::run_sync_local(async move {
            let pairing = std::fs::read(&pairing_path).map_err(|e| format!("Pairing file: {e}"))?;
            let logger = Logger { cb: None, ctx: std::ptr::null_mut() };
            let mut tunnel = connect_tunnel(&pairing, &logger).await?;
            let mut afc = tunnel.connect_afc(&logger).await?;
            let mut file = afc.open(&remote_path, AfcFopenMode::WrOnly).await.map_err(|e| format!("AFC open: {e:?}"))?;
            file.write_entire(&bytes).await.map_err(|e| format!("AFC write: {e:?}"))?;
            file.close().await.map_err(|e| format!("AFC close: {e:?}"))?;
            Ok::<(), String>(())
        })
    });
    match result { Ok(Ok(())) => 0, Ok(Err(e)) | Err(e) => { if !out_error.is_null() { *out_error = cstr(e); } 1 } }
}

pub unsafe fn afc_delete_path(pairing_path: *const c_char, remote_path: *const c_char,
    recursive: i32, out_error: *mut *mut c_char) -> i32 {
    let pairing_path = opt_str(pairing_path, "airlift_pairing.plist");
    let remote_path = opt_str(remote_path, "");
    if !remote_path.starts_with('/') || remote_path == "/" || remote_path.split('/').any(|p| p == "." || p == "..") {
        if !out_error.is_null() { *out_error = cstr("Invalid AFC path; root deletion is forbidden."); } return 1;
    }
    let result = crate::ffi_util::run_with_large_stack("afc_delete_path", move || {
        idevice_ffi::run_sync_local(async move {
            let pairing = std::fs::read(&pairing_path).map_err(|e| format!("Pairing file: {e}"))?;
            let logger = Logger { cb: None, ctx: std::ptr::null_mut() };
            let mut tunnel = connect_tunnel(&pairing, &logger).await?;
            let mut afc = tunnel.connect_afc(&logger).await?;
            if recursive != 0 { afc.remove_all(&remote_path).await.map_err(|e| format!("AFC delete: {e:?}"))?; }
            else { afc.remove(&remote_path).await.map_err(|e| format!("AFC delete: {e:?}"))?; }
            Ok::<(), String>(())
        })
    });
    match result { Ok(Ok(())) => 0, Ok(Err(e)) | Err(e) => { if !out_error.is_null() { *out_error = cstr(e); } 1 } }
}
"""
    if anchor not in src: raise SystemExit("AFC insertion anchor missing")
    src = src.replace(anchor, code + "\n" + anchor, 1)
    exploit_path.write_text(src)

lib = lib_path.read_text()
if "al_afc_write_file(" not in lib:
    anchor = "// ---------------------------------------------------------------------------\n// Exploit file operations"
    code = r"""
#[no_mangle]
pub unsafe extern "C" fn al_afc_write_file(pairing_path: *const c_char, remote_path: *const c_char,
    data: *const u8, data_len: usize, out_error: *mut *mut c_char) -> i32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| exploit::afc_write_file(pairing_path, remote_path, data, data_len, out_error))) {
        Ok(rc) => rc, Err(e) => { if !out_error.is_null() { *out_error = ffi_util::cstr(format!("Rust panic: {e:?}")); } 1 }
    }
}
#[no_mangle]
pub unsafe extern "C" fn al_afc_delete_path(pairing_path: *const c_char, remote_path: *const c_char,
    recursive: i32, out_error: *mut *mut c_char) -> i32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| exploit::afc_delete_path(pairing_path, remote_path, recursive, out_error))) {
        Ok(rc) => rc, Err(e) => { if !out_error.is_null() { *out_error = ffi_util::cstr(format!("Rust panic: {e:?}")); } 1 }
    }
}
"""
    if anchor not in lib: raise SystemExit("lib.rs insertion anchor missing")
    lib = lib.replace(anchor, code + "\n" + anchor, 1)
    lib_path.write_text(lib)

header = header_path.read_text()
if "al_afc_write_file(" not in header:
    anchor = "// Run the AirTraffic sandbox escape."
    decl = """int32_t al_afc_write_file(const char *pairing_path, const char *remote_path,
    const uint8_t *data, size_t data_len, char **out_error);
int32_t al_afc_delete_path(const char *pairing_path, const char *remote_path,
    int32_t recursive, char **out_error);

"""
    if anchor not in header: raise SystemExit("header insertion anchor missing")
    header = header.replace(anchor, decl + anchor, 1)
    header_path.write_text(header)

print("AFC read/write/delete FFI patch applied.")
