/* @toolchord
{
  "apiVersion": 1,
  "id": "hash.sha1",
  "title": "Hash with SHA-1",
  "summary": "Legacy digest; not collision resistant",
  "palette": {
    "group": "hash", "groupTitle": "Hash",
    "aliases": ["sha1", "sha-1", "sha 1"],
    "glyph": "#", "copyNoun": "hash"
  }
}
*/
function preview(input, options, api) {
    return hashText(input, options, api, "sha1");
}

// @shared hash.sha256/hash
// CryptoKit supplies the digest; the tool owns its presentation and warnings.
function hashText(input, options, api, algorithm) {
    const name = {sha256: "SHA-256", sha512: "SHA-512", sha1: "SHA-1", md5: "MD5"}[algorithm];
    const digest = api.native("crypto.digest", algorithm, input);
    const size = api.native("text.byteCountLabel", input);
    const warnings = algorithm === "md5" || algorithm === "sha1"
        ? [name + " is not collision resistant. Use it only for checksums and legacy compatibility."]
        : [];
    return {primaryText: digest, status: name + " · " + size + " hashed", warnings};
}
// @endshared
