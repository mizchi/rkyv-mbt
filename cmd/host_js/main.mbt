///|
/// A no-Rust JavaScript-target example. The `user` package is generated from
/// `examples/host_codegen/user_schema.mbtx`; this client imports that generated
/// schema API and executes the archive encoder and zero-copy reader on JS.
fn main {
  let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U]) catch {
    _ => abort("invalid host value")
  }
  let root = @user.root(archive) catch { _ => abort("invalid host archive") }
  match root.field("name") {
    None => abort("host schema did not expose name")
    Some(name) =>
      match root.field("scores") {
        None => abort("host schema did not expose scores")
        Some(scores) => {
          let name = name.read_string() catch {
            _ => abort("invalid host string")
          }
          let scores = scores.read_vec_u32() catch {
            _ => abort("invalid host vector")
          }
          match name {
            None => abort("host schema did not match its name view")
            Some(name) =>
              match scores {
                None => abort("host schema did not match its score view")
                Some(scores) => println("\{name}: \{scores.length()} scores")
              }
          }
        }
      }
  }
}
