#include "OSCrypt.h"

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <stdlib.h>
#include <string.h>

char *oscrypt_decrypt_v10(const void *ciphertext, size_t ciphertext_len,
                          const void *password, size_t password_len) {
    if (ciphertext == NULL || ciphertext_len == 0 || password == NULL || password_len == 0) {
        return NULL;
    }

    unsigned char key[16];
    const char salt[] = "saltysalt";
    int derived = CCKeyDerivationPBKDF(
        kCCPBKDF2,
        password,
        password_len,
        (const unsigned char *)salt,
        9,
        kCCPRFHmacAlgSHA1,
        1003,
        key,
        sizeof(key)
    );
    if (derived != kCCSuccess) {
        memset(key, 0, sizeof(key));
        return NULL;
    }

    unsigned char iv[16];
    memset(iv, 0x20, sizeof(iv));

    size_t outCap = ciphertext_len + kCCBlockSizeAES128;
    unsigned char *out = malloc(outCap);
    if (out == NULL) {
        memset(key, 0, sizeof(key));
        return NULL;
    }

    size_t moved = 0;
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES128,
        kCCOptionPKCS7Padding,
        key,
        sizeof(key),
        iv,
        ciphertext,
        ciphertext_len,
        out,
        outCap,
        &moved
    );
    memset(key, 0, sizeof(key));
    memset(iv, 0, sizeof(iv));

    if (status != kCCSuccess || moved == 0) {
        memset(out, 0, outCap);
        free(out);
        return NULL;
    }

    char *text = malloc(moved + 1);
    if (text == NULL) {
        memset(out, 0, outCap);
        free(out);
        return NULL;
    }
    memcpy(text, out, moved);
    text[moved] = '\0';
    memset(out, 0, outCap);
    free(out);
    return text;
}
