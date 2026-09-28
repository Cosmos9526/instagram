{{flutter_js}}
{{flutter_build_config}}

// The server replaces __ASSET_BASE__ with "v/<build>/": every deploy loads fonts and images from new URLs,
// so a browser never reuses an icon font cached from an older build. No service worker is registered.
_flutter.loader.load({
  config: { assetBase: "__ASSET_BASE__".startsWith("__") ? "" : "__ASSET_BASE__" },
});
