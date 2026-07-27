///|
/// A no-Rust JavaScript-target example. The `user` package is generated from
/// `examples/host_codegen/user_schema.mbtx`; this client imports that generated
/// schema API and executes the archive encoder and zero-copy reader on JS.
fn main {
  let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U]) catch {
    _ => abort("invalid host value")
  }
  let mutable = @user.UserMutView::root(archive.mut_view()) catch {
    _ => abort("invalid mutable host archive")
  }
  let patched = mutable.set_name_same_length("Eve") catch {
    _ => abort("invalid generated string")
  }
  if !patched {
    abort("generated name could not be patched in place")
  }
  let root = @user.UserView::root(Bytes::from_array(archive)) catch {
    _ => abort("invalid host archive")
  }
  let name = root.name() catch { _ => abort("invalid host string") }
  let scores = root.scores() catch { _ => abort("invalid host vector") }
  println("\{name}: \{scores.length()} scores")
}
