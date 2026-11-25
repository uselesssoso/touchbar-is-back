#pragma once

#include <stddef.h>

// Decrypt a Chromium OSCrypt "v10" AES-128-CBC payload (bytes after the "v10"
// prefix). password is the Safe Storage secret from the Keychain.
// Returns a malloc'd NUL-terminated UTF-8 string the caller must free, or NULL.
char *oscrypt_decrypt_v10(const void *ciphertext, size_t ciphertext_len,
                          const void *password, size_t password_len);
