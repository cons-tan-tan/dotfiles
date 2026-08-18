use std::ffi::c_void;
use std::io;
use std::ptr;

use windows_sys::Win32::Foundation::LocalFree;
use windows_sys::Win32::Security::Cryptography::{
    CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData,
};
use zeroize::Zeroize;

struct LocalBlob(CRYPT_INTEGER_BLOB);

impl LocalBlob {
    fn copy(&self) -> Vec<u8> {
        if self.0.cbData == 0 || self.0.pbData.is_null() {
            return Vec::new();
        }
        // SAFETY: DPAPI returned a buffer of cbData bytes owned by LocalAlloc.
        unsafe { std::slice::from_raw_parts(self.0.pbData, self.0.cbData as usize).to_vec() }
    }
}

impl Drop for LocalBlob {
    fn drop(&mut self) {
        if self.0.pbData.is_null() {
            return;
        }
        // SAFETY: DPAPI returned this LocalAlloc buffer and it remains valid until LocalFree.
        unsafe {
            std::slice::from_raw_parts_mut(self.0.pbData, self.0.cbData as usize).zeroize();
            let _ = LocalFree(self.0.pbData.cast::<c_void>());
        }
    }
}

fn input_blob(input: &mut [u8]) -> io::Result<CRYPT_INTEGER_BLOB> {
    Ok(CRYPT_INTEGER_BLOB {
        cbData: input
            .len()
            .try_into()
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "input is too large"))?,
        pbData: input.as_mut_ptr(),
    })
}

pub fn protect(input: &mut [u8]) -> io::Result<Vec<u8>> {
    let input = input_blob(input)?;
    let mut output = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: ptr::null_mut(),
    };
    // SAFETY: all pointers are valid for this call; optional parameters are null.
    let success = unsafe {
        CryptProtectData(
            &input,
            windows_sys::w!("wsl-dpapi-v1"),
            ptr::null(),
            ptr::null_mut(),
            ptr::null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    };
    if success == 0 {
        return Err(io::Error::last_os_error());
    }
    let output = LocalBlob(output);
    Ok(output.copy())
}

pub fn unprotect(input: &mut [u8]) -> io::Result<Vec<u8>> {
    let input = input_blob(input)?;
    let mut output = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: ptr::null_mut(),
    };
    // SAFETY: all pointers are valid for this call; optional parameters are null.
    let success = unsafe {
        CryptUnprotectData(
            &input,
            ptr::null_mut(),
            ptr::null(),
            ptr::null_mut(),
            ptr::null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    };
    if success == 0 {
        return Err(io::Error::last_os_error());
    }
    let output = LocalBlob(output);
    Ok(output.copy())
}
