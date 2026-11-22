// CryptoKit supplies the digest; the tool owns its presentation and warnings.
function preview(input, options, api) {
    const algorithm = api.id.split(".")[1];
    const name = {sha256: "SHA-256", sha512: "SHA-512", sha1: "SHA-1", md5: "MD5"}[algorithm];
    const digest = api.native("crypto.digest", algorithm, input);
    const size = api.native("text.byteCountLabel", input);
    const warnings = algorithm === "md5" || algorithm === "sha1"
        ? [name + " is not collision resistant. Use it only for checksums and legacy compatibility."]
        : [];
    return {primaryText: digest, status: name + " · " + size + " hashed", warnings};
}
