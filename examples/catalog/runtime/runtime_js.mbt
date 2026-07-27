///|
/// Reads a binary archive through Node's `readFileSync`. Node's `Buffer` is a
/// `Uint8Array`, which is the JavaScript representation of MoonBit `Bytes`, so
/// the archive is borrowed without an additional byte copy.
#module("node:fs")
pub extern "js" fn read_binary(path : String) -> Bytes = "readFileSync"

///|
/// Writes an archive with Node's synchronous filesystem API. `Bytes` lowers to
/// `Uint8Array`, so Node consumes the generated archive without conversion.
#module("node:fs")
pub extern "js" fn write_binary(path : String, bytes : Bytes) -> Unit = "writeFileSync"
