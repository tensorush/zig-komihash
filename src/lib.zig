//! Root library file that exposes the public API.

pub const Komirand = @import("Komirand.zig").Komirand;
pub const Komihash = @import("komihash.zig").Komihash;
pub const KomihashStateless = @import("komihash.zig").KomihashStateless;
