# The arena renders in the iOS Simulator (OpenGL ES 3), measured 2026-09-13

This supersedes the "rendering on the simulator is impossible" finding in `docs/stage1-results.md`.
The arena now draws inside the SwiftUI `GodotAppView` on the iPhone 17 simulator. The device path
is untouched and still Metal.

Proof: `/private/tmp/claude-502/-Users-white/a5c18233-feca-44b1-a2c3-1eeeeb05df02/scratchpad/gl2.png`
is a screenshot of the running simulator showing the 3D arena floor, its hazard-striped kerb, the
centre spikes and the Godot-drawn HUD ("PLAYER vs OPPONENT", "1:30", "SCRAP 0").

## Why it did not work, and what the fix is

The prebuilt `libgodot-ios.xcframework` (SwiftGodotKit rev `dabb72c`, binary from
`migueldeicaza/godot` release v4.6.4, engine commit `d064e255`) has a simulator slice with no
Metal: `platform/ios/detect.py` line 154 forces `metal = False` whenever `simulator=yes`, so the
slice reports only `opengl3` and `dummy`. That leaves OpenGL as the only real driver, and the
embedded display server's OpenGL branch was written for the standalone app only:

```objc
// drivers/apple_embedded/display_server_apple_embedded.mm, before the patch
if (rendering_driver == "opengl3") {
    CALayer *layer = [GDTAppDelegateService.viewController.godotView initializeRenderingForDriver:@"opengl3"];
    if (!layer) { ERR_FAIL_MSG("Failed to create iOS OpenGLES rendering layer."); }
```

`GDTAppDelegateService.viewController` is the standalone app's view controller. When libgodot is
embedded there is no such view controller, the expression is `nil`, and the display server dies.
The Metal branch, by contrast, already handles embedding: it takes the `CALayer` the host hands
over through `DisplayServerAppleEmbedded::set_native_surface()`.

The fix gives the OpenGL branch the same treatment. When a native surface exists, the display
server creates its own `GDTOpenGLLayer` (the `CAEAGLLayer` subclass that already lives in
`platform/ios/display_layer_ios.mm`), sizes it to the host layer, adds it as a **sublayer** of the
host layer (SwiftGodotKit hands over a `CAMetalLayer`; a `CAEAGLLayer` composites inside it fine),
and calls `initializeDisplayLayer`. Per-frame drive is split across the two hooks the embedded host
already calls:

| standalone (`GDTView::drawView`) | embedded (patched) |
|---|---|
| `[renderingLayer startRenderDisplayLayer]` | `DisplayServerAppleEmbedded::process_events()`, the first thing `GodotInstance::iteration()` calls |
| `OS_AppleEmbedded::iterate()` | `Main::iteration()`, called by `GodotInstance::iteration()` |
| `[renderingLayer stopRenderDisplayLayer]` | `DisplayServerAppleEmbedded::swap_buffers()`, called by `RasterizerGLES3::gl_end_frame()` at the end of `Main::iteration()` |

Two more things were needed:

- `window_surfaces[MAIN_WINDOW_ID] = native_surface` in the GL branch. Only the `RD_ENABLED` branch
  was doing it, and without it `window_get_size()` falls through to
  `GDTAppDelegateService.viewController.view.bounds`, which is a zero rect when embedded.
- `GDTOpenGLLayer initializeDisplayLayer` only made an ES 3 context when
  `GLOBAL_GET("rendering/renderer/rendering_method") == "gl_compatibility"`. A command-line
  `--rendering-method` (which is how an embedded host forces the method) does **not** write back to
  that project setting, it only calls `OS::set_current_rendering_method()`. The setting still read
  `mobile`, so the context was never created and the layer silently failed. The check is gone; the
  layer is only ever built for the `opengl3` driver, which always means gl_compatibility.

`resize_window()` re-reads the host layer's bounds and `contentsScale`, updates the GL layer's frame
and calls `layoutDisplayLayer`, which tears down and rebuilds the renderbuffers and re-publishes
`GLES3::TextureStorage::system_fbo`. The destructor detaches the layer.

Everything is guarded by `#if defined(GLES3_ENABLED)`, which is only ever set on `platform=ios`
(`platform/visionos/detect.py` forces `opengl3 = False`), so visionOS is unaffected. The device
slice keeps `metal=yes`, takes the `RD_ENABLED` path, and never creates a GL layer, so `gl_layer`
is `nullptr` there and every hook above is a no-op.

### The simulator really does have OpenGL ES

Worth recording because the opposite is widely assumed. The iOS 26.5 simulator runtime ships a full
`OpenGLES.framework`:

```
/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/CoreSimulator/Profiles/
  Runtimes/iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/
  OpenGLES.framework/OpenGLES     Mach-O 64-bit dynamically linked shared library arm64
```

`nm -gU` on it exports `EAGLContext` and all 38 `*OES` entry points `GDTOpenGLLayer` uses
(`glGenFramebuffersOES`, `glRenderbufferStorageOES`, `glGetRenderbufferParameterivOES`, …).
Note `xcrun simctl spawn <udid> /bin/ls /System/Library/Frameworks` lists the **host's** frameworks,
not the runtime's, so it is a useless way to check this. Read the runtime root instead.

## The engine patch

Against `https://github.com/migueldeicaza/godot`, branch `swiftgodotkit-4.6`, commit `d064e255`
(the exact commit the shipped 4.6.4 binary self-reports as `4.6.1.rc.gh.d064e255e`).
Saved verbatim at `~/Build/godot-embedded-gl.patch` (166 lines).

```diff
diff --git a/drivers/apple_embedded/display_server_apple_embedded.h b/drivers/apple_embedded/display_server_apple_embedded.h
--- a/drivers/apple_embedded/display_server_apple_embedded.h
+++ b/drivers/apple_embedded/display_server_apple_embedded.h
@@ -51,6 +51,8 @@
 
 #if defined(GLES3_ENABLED)
 #include "drivers/gles3/rasterizer_gles3.h"
+
+#import "drivers/apple_embedded/display_layer_apple_embedded.h"
 #endif // GLES3_ENABLED
 
 #import <Foundation/Foundation.h>
@@ -67,6 +69,12 @@ class DisplayServerAppleEmbedded : public DisplayServer {
 #endif
 	NativeMenu *native_menu = nullptr;
 
+#if defined(GLES3_ENABLED)
+	// Only set when the host embeds us (a native surface was handed over) and the
+	// rendering driver is "opengl3": our own CAEAGLLayer, hosted inside the host's layer.
+	CALayer<GDTDisplayLayer> *gl_layer = nullptr;
+#endif
+
 	id tts = nullptr;
 
 	DisplayServer::ScreenOrientation screen_orientation;
@@ -245,7 +253,7 @@ public:
 	void resize_window(Size2i p_size, WindowID p_id);
 	void resize_window(CGSize size);
 	void set_content_scale(float p_scale);
-	virtual void swap_buffers() override {}
+	virtual void swap_buffers() override;
 
 	virtual void set_native_icon(const String &p_filename) override;
 	virtual void set_icon(const Ref<Image> &p_icon) override;
diff --git a/drivers/apple_embedded/display_server_apple_embedded.mm b/drivers/apple_embedded/display_server_apple_embedded.mm
--- a/drivers/apple_embedded/display_server_apple_embedded.mm
+++ b/drivers/apple_embedded/display_server_apple_embedded.mm
@@ -42,6 +42,10 @@
 #include "core/config/project_settings.h"
 #include "core/io/file_access_pack.h"
 
+#if defined(GLES3_ENABLED)
+#import "platform/ios/display_layer_ios.h"
+#endif
+
 #import <GameController/GameController.h>
 
 static const float kDisplayServerIOSAcceleration = 1.f;
@@ -196,7 +200,28 @@
 
 #if defined(GLES3_ENABLED)
 	if (rendering_driver == "opengl3") {
-		CALayer *layer = [GDTAppDelegateService.viewController.godotView initializeRenderingForDriver:@"opengl3"];
+		CALayer *layer = nullptr;
+
+		// When embedded, the host (e.g. SwiftGodotKit) hands us a CALayer through
+		// set_native_surface() and there is no GDTAppDelegateService.viewController at all.
+		// Host our own CAEAGLLayer inside that layer instead of asking the standalone view
+		// controller's view to make one.
+		CALayer *host_layer = _get_layer_from_native_surface(native_surface);
+		if (host_layer) {
+			GODOT_CLANG_WARNING_PUSH_AND_IGNORE("-Wdeprecated-declarations") // OpenGL ES is deprecated in iOS 12.0.
+			GDTOpenGLLayer *embedded_layer = [GDTOpenGLLayer layer];
+			GODOT_CLANG_WARNING_POP
+			embedded_layer.frame = host_layer.bounds;
+			embedded_layer.contentsScale = host_layer.contentsScale;
+			[host_layer addSublayer:embedded_layer];
+			[embedded_layer initializeDisplayLayer];
+
+			gl_layer = embedded_layer;
+			layer = embedded_layer;
+			window_surfaces[MAIN_WINDOW_ID] = native_surface;
+		} else {
+			layer = [GDTAppDelegateService.viewController.godotView initializeRenderingForDriver:@"opengl3"];
+		}
 
 		if (!layer) {
 			ERR_FAIL_MSG("Failed to create iOS OpenGLES rendering layer.");
@@ -236,6 +261,13 @@
 		rendering_context = nullptr;
 	}
 #endif
+#if defined(GLES3_ENABLED)
+	if (gl_layer) {
+		[gl_layer removeFromSuperlayer];
+		gl_layer = nullptr;
+	}
+#endif
+
 	native_surface = nullptr;
 	window_surfaces.clear();
 }
@@ -280,9 +312,26 @@
 }
 
 void DisplayServerAppleEmbedded::process_events() {
+#if defined(GLES3_ENABLED)
+	// Embedded GL: nothing drives the layer for us, so bind the drawable at the top of
+	// every host-driven iteration, the way GDTView::drawView does when standalone.
+	if (gl_layer) {
+		[gl_layer startRenderDisplayLayer];
+	}
+#endif
+
 	Input::get_singleton()->flush_buffered_events();
 }
 
+void DisplayServerAppleEmbedded::swap_buffers() {
+#if defined(GLES3_ENABLED)
+	// Called by RasterizerGLES3::gl_end_frame() at the end of Main::iteration().
+	if (gl_layer) {
+		[gl_layer stopRenderDisplayLayer];
+	}
+#endif
+}
+
 void DisplayServerAppleEmbedded::_dispatch_input_events(const Ref<InputEvent> &p_event) {
 	Ref<InputEventFromWindow> event_from_window = p_event;
 	WindowID window_id = INVALID_WINDOW_ID;
@@ -955,6 +1004,16 @@ void DisplayServerAppleEmbedded::resize_window(Size2i p_size, WindowID p_id) {
 		rendering_context->window_set_size(p_id, size.x, size.y);
 	}
 #endif
+#if defined(GLES3_ENABLED)
+	if (gl_layer && p_id == MAIN_WINDOW_ID) {
+		CALayer *host_layer = _get_layer_from_native_surface(native_surface);
+		if (host_layer) {
+			gl_layer.frame = host_layer.bounds;
+			gl_layer.contentsScale = host_layer.contentsScale;
+		}
+		[gl_layer layoutDisplayLayer];
+	}
+#endif
 
 	Variant resize_rect = Rect2i(Point2i(), size);
 	Callable *callback = window_resize_callbacks.getptr(p_id);
diff --git a/platform/ios/display_layer_ios.mm b/platform/ios/display_layer_ios.mm
--- a/platform/ios/display_layer_ios.mm
+++ b/platform/ios/display_layer_ios.mm
@@ -89,14 +89,15 @@ - (void)initializeDisplayLayer {
 			kEAGLDrawablePropertyColorFormat,
 			nil];
 
-	// Create GL ES 3 context
-	if (GLOBAL_GET("rendering/renderer/rendering_method") == "gl_compatibility") {
-		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
-		NSLog(@"Setting up an OpenGL ES 3.0 context.");
-		if (!context) {
-			NSLog(@"Failed to create OpenGL ES 3.0 context!");
-			return;
-		}
+	// Create GL ES 3 context. This layer is only ever created for the "opengl3" rendering
+	// driver, which always implies the gl_compatibility rendering method, so do not gate on
+	// the project setting: when the method is forced on the command line (as an embedded host
+	// does) the setting still reads "mobile"/"forward_plus" and the context would never be made.
+	context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
+	NSLog(@"Setting up an OpenGL ES 3.0 context.");
+	if (!context) {
+		NSLog(@"Failed to create OpenGL ES 3.0 context!");
+		return;
 	}
 
 	if (![EAGLContext setCurrentContext:context]) {
```

## How to rebuild it

Everything lives outside the iCloud-synced `~/Documents` tree, in `~/Build`. Nothing in `~/Build`
is in the repo; only the patch above and this file are.

```bash
# 1. Engine source, ~400 MB. The branch head must be d064e255 to match the shipped device slice.
mkdir -p ~/Build && cd ~/Build
git clone --depth 1 -b swiftgodotkit-4.6 https://github.com/migueldeicaza/godot godot
cd godot && git apply ~/Build/godot-embedded-gl.patch

# 2. Simulator arm64 slice only. scons is a user install, not on PATH by default.
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
scons platform=ios arch=arm64 simulator=yes target=template_release \
      vulkan=no metal=no opengl3=yes debug_symbols=no disable_path_overrides=no -j8
# -> bin/libgodot.ios.template_release.arm64.simulator.a

# 3. Package. Start from the stock xcframework that SwiftPM already downloaded, so the DEVICE
#    slice stays byte-identical to the released v4.6.4 binary. cp -Rc is an APFS clone, so this
#    costs no disk.
cp -Rc ~/Library/Developer/Xcode/DerivedData/Roboteer-*/SourcePackages/artifacts/swiftgodotkit/\
ios_libgodot/libgodot.xcframework ~/Build/SwiftGodotKit/build/ios/
XC=~/Build/SwiftGodotKit/build/ios/libgodot.xcframework
mkdir -p "$XC/ios-arm64-simulator/Headers"
cp -c "$XC/ios-arm64_x86_64-simulator/Headers/"*.h "$XC/ios-arm64-simulator/Headers/"
cp ~/Build/godot/bin/libgodot.ios.template_release.arm64.simulator.a \
   "$XC/ios-arm64-simulator/libgodotkit.ios.simulator.a"
rm -rf "$XC/ios-arm64_x86_64-simulator"
/usr/libexec/PlistBuddy -c "Set :AvailableLibraries:1:LibraryIdentifier ios-arm64-simulator" "$XC/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:1:SupportedArchitectures:1" "$XC/Info.plist"

# 4. Local SwiftGodotKit at the pinned revision, pointed at that xcframework.
cd ~/Build && git clone https://github.com/migueldeicaza/SwiftGodotKit
cd SwiftGodotKit && git checkout dabb72ced0bc6b03114e0e31f743b5d889edc433
# then edit Package.swift: iosLibgodotTarget becomes
#   .binaryTarget(name: "ios_libgodot", path: "build/ios/libgodot.xcframework")
# The macOS target keeps its remote url/checksum.
```

`~/Build/package.sh` does step 3 in one go.

### Measurements

| item | value |
|---|---|
| engine clone | 399 MB |
| scons wall time, 8 jobs, warm (the run that finished) | 3 min 56 s |
| scons wall time from cold, same flags | about 25 min |
| peak `bin/obj` | 303 MB (deleted afterwards; the `.a` does not need it) |
| patched simulator `.a`, arm64 only | 159,997,096 bytes (153 MB) |
| stock simulator `.a`, arm64 + x86_64 fat | 335,551,712 bytes (320 MB) |
| device `.a`, untouched | 179,968,040 bytes |
| whole custom xcframework | 1.3 GB (the stock `Headers/` folders carry copies of the libs; left as shipped) |
| simulator Debug `Roboteer.app` | 142 MB, `Roboteer.debug.dylib` 72.5 MB |

Disk on this Mac was the real constraint: free space went from 6.5 GB to 1.3 GB during the build
and had to be recovered by deleting `bin/obj` and stale DerivedData. Budget 5 GB.

## The Xcode side

`Roboteer.xcodeproj/project.pbxproj`, one section replaced. `XCSwiftPackageProductDependency`
`AA0000000000000000000061` keeps its `package = AA0000000000000000000060` reference and builds fine.

```diff
-/* Begin XCRemoteSwiftPackageReference section */
-		AA0000000000000000000060 /* XCRemoteSwiftPackageReference "SwiftGodotKit" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/migueldeicaza/SwiftGodotKit";
-			requirement = {
-				kind = revision;
-				revision = dabb72ced0bc6b03114e0e31f743b5d889edc433;
-			};
-		};
-/* End XCRemoteSwiftPackageReference section */
+/* Begin XCLocalSwiftPackageReference section */
+		AA0000000000000000000060 /* XCLocalSwiftPackageReference "SwiftGodotKit" */ = {
+			isa = XCLocalSwiftPackageReference;
+			relativePath = ../../../Build/SwiftGodotKit;
+		};
+/* End XCLocalSwiftPackageReference section */
```

`relativePath` is resolved from the directory containing `Roboteer.xcodeproj`, so
`~/Documents/Code/Roboteer` + `../../../Build/SwiftGodotKit` = `~/Build/SwiftGodotKit`.

**This makes the project non-portable.** Anyone cloning Roboteer onto another Mac has to build the
patched libgodot first, or revert this hunk to the remote reference and lose simulator rendering.
When the change is upstreamed, or when a `libgodot` release ships with it, revert to the remote
reference.

Swift side, both minimal:

- `Roboteer/ArenaHost.swift`: the `#if targetEnvironment(simulator)` defaults are now
  `opengl3` / `gl_compatibility` / `embedded`. The headless arena is still one launch argument away:
  `-godotDriver dummy -godotMethod dummy -godotDisplay headless`.
- `Roboteer/FightView.swift`: the full-screen "renders on a real iPhone" panel, and the opaque
  `Stage.ground` behind it that was hiding the Godot view, are gone. What is left is a small
  non-interactive bottom-left capsule reading `SIMULATOR: OPENGL ES 3`.

Both destinations link. Verified 2026-09-13 with the local package in place:

| build | result |
|---|---|
| `-destination 'platform=iOS Simulator,id=A18A1779-...'`, Debug | no errors, app runs and renders |
| `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`, Debug | `** BUILD SUCCEEDED **`, 178 MB `.app` |

`otool -L` on the device binary still shows `MetalFX` (weak) and `Metal`, and the device slice of
the xcframework is the byte-identical file cloned out of the released v4.6.4 artifact.

Note: other agents were building the same project concurrently, which makes `xcodebuild` fail with
`unable to attach DB: ... database is locked`. That is contention on the shared DerivedData, not a
build error; retry, or pass your own `-derivedDataPath`.

Build and run:

```bash
xcodebuild build -project Roboteer.xcodeproj -scheme Roboteer -configuration Debug \
  -destination 'platform=iOS Simulator,id=A18A1779-2368-4FFF-9195-1523D4ABA146' -quiet
xcrun simctl install A18A1779-2368-4FFF-9195-1523D4ABA146 <path>/Roboteer.app
xcrun simctl launch A18A1779-2368-4FFF-9195-1523D4ABA146 com.radicraft.roboteer -autoFight
```

## What works, and what was not measured

**Works, observed:**

- The arena renders. Godot's own boot splash draws first, then the 3D arena floor, kerb, spikes and
  the Godot HUD, all inside the SwiftUI view with the SwiftUI overlay composited on top of it.
- Resize. The `CAMetalLayer` SwiftGodotKit creates starts as a square the size of the longest screen
  edge and is only cut down to the view bounds on the first `layoutSubviews`. The arena came out
  correctly proportioned at the simulator's full 2622 x 1206, which only happens if
  `resize_window` -> `layoutDisplayLayer` rebuilt the renderbuffers at the new size.
- No GL errors. `GDTOpenGLLayer stopRenderDisplayLayer` calls `glGetError()` every frame under
  `DEBUG_ENABLED` and logs `DrawView: %x error`; nothing like it appears in the log. The only engine
  error in a clean run is the pre-existing, harmless
  `class_db.cpp:787:set_object_extension_instance(): Class 'DisplayServer' has no native extension`,
  which the stock build prints too.

**Reasoned, not measured:**

- Touch. The simulator offers no way to inject a tap (`simctl io` does recording and screenshots
  only, there is no touch verb), and clicking the owner's visible simulator window was not
  appropriate. The argument that it is unaffected is structural: `UIGodotAppView.touchesBegan` ->
  `DisplayServerAppleEmbeddedBridge.touchPress` -> `DisplayServerAppleEmbedded::touch_press` ->
  `Input` never touches the renderer. The one place the renderer could have leaked in is coordinate
  scaling, which SwiftGodotKit does with the **host** layer's `contentsScale` and frame origin; the
  GL layer is created with exactly that frame and that `contentsScale`, so screen points map to
  Godot pixels identically to the Metal path. **Owed: one tap on the fight screen.**
- Frame rate. Not instrumented. The simulator's OpenGL ES goes through a software-ish translation
  layer and will be slower than the device; treat the simulator as a correctness check, not a
  performance one.

**What the app itself shows today (2026-09-13, mid Stage 4 refactor):**

The engine draws. Roboteer's own view layering does not yet let you see it, and that is not the
renderer:

- Launched plain, the menu's stage is black once `arena_ready` clears the rendered still. The log
  says `arena_log warn: unknown message type: workshop_config` -- the Arena project has no stage
  scene for the menu yet, so Godot is drawing an empty scene.
- Launched with `-autoFight`, the fight screen is black. `RootView` puts the single `GodotSurface`
  behind `MenuView`, and `MenuView` is a `NavigationStack`; a pushed `navigationDestination` gets
  an opaque container background, so `FightView` covers the Godot view it is meant to sit on.
  Removing the `Stage.ground` fill from `FightView` (done) is necessary but not sufficient; the
  navigation container's own background has to be cleared too.

Neither of those appears in the standalone harness, which puts a `GodotAppView` straight in a
`WindowGroup` and renders the same `arena.pck` correctly. Both are Stage 4 Swift work, owed to
whoever owns `StageSurface.swift` / `MenuView.swift`.

**Known rough edges:**

- The GL layer is a sublayer of the host `CAMetalLayer`, which is itself never presented to. That is
  fine (Core Animation composites the sublayer), but it means two layers exist where one would do.
  A tidier patch would let the host choose the layer class.
- `x86_64` simulators are no longer supported by this xcframework. The slice is arm64 only. Nobody
  here runs an Intel Mac.
- The patch is not upstream. Any `libgodot` version bump has to re-apply it.

## The verification harness

The repo was being edited by other agents during this work, so the rendering was proved in a
throwaway copy at `~/Build/RoboteerTest` whose app target compiles exactly one file, `Spike/GLSpike.swift`:
an `@main` SwiftUI app that puts a `GodotAppView` on screen with
`GodotApp(packFile: "arena.pck", renderingDriver: "opengl3", renderingMethod: "gl_compatibility", displayDriver: "embedded")`.
That is the whole harness, and it is a useful thing to keep: it isolates "does the engine draw"
from every question about Roboteer's own Swift.
