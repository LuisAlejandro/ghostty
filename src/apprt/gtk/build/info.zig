const builtin = @import("builtin");

/// Base application ID
pub const base_application_id = "app.mash.Mash";

/// GTK application ID
pub const application_id = switch (builtin.mode) {
    .Debug, .ReleaseSafe => base_application_id ++ "-debug",
    .ReleaseFast, .ReleaseSmall => base_application_id,
};

pub const resource_path = "/app/mash/Mash";

/// GTK object path
pub const object_path = switch (builtin.mode) {
    .Debug, .ReleaseSafe => resource_path ++ "_debug",
    .ReleaseFast, .ReleaseSmall => resource_path,
};
