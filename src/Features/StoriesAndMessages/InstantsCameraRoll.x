#import "../../Utils.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// SCIInstantsPickerDelegate
// Standalone delegate class for PHPickerViewController.
// Holds a weak ref to the camera VC so we can forward the picked image.
// ---------------------------------------------------------------------------

@interface SCIInstantsPickerDelegate : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *cameraViewController;
- (instancetype)initWithCameraViewController:(UIViewController *)cameraVC;
@end

@implementation SCIInstantsPickerDelegate

- (instancetype)initWithCameraViewController:(UIViewController *)cameraVC {
    self = [super init];
    if (self) {
        _cameraViewController = cameraVC;
    }
    return self;
}

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results {

    // Dismiss the picker first
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (results.count == 0) return;

    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;

    if (![provider canLoadObjectOfClass:[UIImage class]]) {
        NSLog(@"[SCInsta] InstantsCameraRoll: provider cannot load UIImage");
        return;
    }

    UIViewController *cameraVC = self.cameraViewController;
    if (!cameraVC) {
        NSLog(@"[SCInsta] InstantsCameraRoll: cameraVC was deallocated");
        return;
    }

    [provider loadObjectOfClass:[UIImage class]
              completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        if (error) {
            NSLog(@"[SCInsta] InstantsCameraRoll: failed to load image — %@", error);
            return;
        }

        UIImage *image = (UIImage *)object;
        if (!image) {
            NSLog(@"[SCInsta] InstantsCameraRoll: loaded object is not a UIImage");
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // --- Attempt to call the capture-pipeline method ---
            // The real selector is unknown; try the most likely candidates.
            // If none work the image won't advance — check logs for the
            // method dump below to find the correct one.

            SEL primarySel   = NSSelectorFromString(@"didCapturePhoto:");
            SEL altSel1      = NSSelectorFromString(@"handleCapturedPhoto:");
            SEL altSel2      = NSSelectorFromString(@"processCapturedImage:");
            SEL altSel3      = NSSelectorFromString(@"quicksnapDidCapturePhoto:");

            if ([cameraVC respondsToSelector:primarySel]) {
                NSLog(@"[SCInsta] InstantsCameraRoll: calling didCapturePhoto:");
                ((void (*)(id, SEL, id))objc_msgSend)(cameraVC, primarySel, image);
            } else if ([cameraVC respondsToSelector:altSel1]) {
                NSLog(@"[SCInsta] InstantsCameraRoll: calling handleCapturedPhoto:");
                ((void (*)(id, SEL, id))objc_msgSend)(cameraVC, altSel1, image);
            } else if ([cameraVC respondsToSelector:altSel2]) {
                NSLog(@"[SCInsta] InstantsCameraRoll: calling processCapturedImage:");
                ((void (*)(id, SEL, id))objc_msgSend)(cameraVC, altSel2, image);
            } else if ([cameraVC respondsToSelector:altSel3]) {
                NSLog(@"[SCInsta] InstantsCameraRoll: calling quicksnapDidCapturePhoto:");
                ((void (*)(id, SEL, id))objc_msgSend)(cameraVC, altSel3, image);
            } else {
                NSLog(@"[SCInsta] InstantsCameraRoll: ⚠️ No known capture selector found!");
                NSLog(@"[SCInsta] InstantsCameraRoll: Camera VC class: %@", NSStringFromClass([cameraVC class]));

                // Dump all methods so the developer can find the right one
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList([cameraVC class], &methodCount);
                NSLog(@"[SCInsta] InstantsCameraRoll: --- Method dump (%u methods) ---", methodCount);
                for (unsigned int i = 0; i < methodCount; i++) {
                    SEL sel = method_getName(methods[i]);
                    NSLog(@"[SCInsta]   %@", NSStringFromSelector(sel));
                }
                free(methods);
                NSLog(@"[SCInsta] InstantsCameraRoll: --- End method dump ---");
            }
        });
    }];
}

@end


// ---------------------------------------------------------------------------
// Associated-object key for the picker delegate
// ---------------------------------------------------------------------------
static const char kSCIPickerDelegateKey;


// ---------------------------------------------------------------------------
// Hook: IGQuickSnapCreationCore.IGQuickSnapCreationViewController
// (Swift-mangled name for Logos compatibility)
// ---------------------------------------------------------------------------

@interface _TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController : UIViewController
@end

@interface UIView (SCIDump)
- (void)sc_dumpControls;
@end

@implementation UIView (SCIDump)
- (void)sc_dumpControls {
    if ([self isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)self;
        NSSet *targets = [control allTargets];
        for (id target in targets) {
            NSArray *actions = [control actionsForTarget:target forControlEvent:UIControlEventAllEvents];
            if (actions.count > 0) {
                os_log(OS_LOG_DEFAULT, "[SCInsta] 🔘 BUTTON FOUND: %{public}s", class_getName([self class]));
                os_log(OS_LOG_DEFAULT, "[SCInsta]   Target: %{public}s", class_getName([target class]));
                for (NSString *action in actions) {
                    os_log(OS_LOG_DEFAULT, "[SCInsta]   Action: %{public}s", action.UTF8String);
                }
            }
        }
    }
    for (UIView *subview in self.subviews) {
        [subview sc_dumpControls];
    }
}
@end

%hook _TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    os_log(OS_LOG_DEFAULT, "[SCInsta] 🔍 --- DIAGNOSTIC DUMP START ---");
    
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    
    os_log(OS_LOG_DEFAULT, "[SCInsta] 🔍 --- QUICKSNAP CLASS DUMP START ---");
    for (int i = 0; i < numClasses; i++) {
        const char *className = class_getName(classes[i]);
        if (className) {
            NSString *nameStr = [NSString stringWithUTF8String:className];
            if ([[nameStr lowercaseString] containsString:@"quicksnap"]) {
                os_log(OS_LOG_DEFAULT, "[SCInsta] 🧩 %{public}s", className);
            }
        }
    }
    free(classes);
    os_log(OS_LOG_DEFAULT, "[SCInsta] 🔍 --- QUICKSNAP CLASS DUMP END ---");
}

- (void)viewDidLoad {
    %orig;

    if (![SCIUtils getBoolPref:@"instants_upload_from_library"]) return;

    // --- Build the camera-roll button ---
    UIImageSymbolConfiguration *symbolConfig =
        [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:symbolConfig];

    UIButton *libraryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [libraryButton setImage:icon forState:UIControlStateNormal];
    libraryButton.tintColor = [UIColor whiteColor];

    // Blur pill background so it's visible over any camera feed
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.layer.cornerRadius = 22;
    blurView.clipsToBounds = YES;
    blurView.userInteractionEnabled = NO;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;

    [libraryButton insertSubview:blurView atIndex:0];

    // Layout
    libraryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:libraryButton];

    [NSLayoutConstraint activateConstraints:@[
        // Button position: bottom-left, safe area aware
        [libraryButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [libraryButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [libraryButton.widthAnchor constraintEqualToConstant:44],
        [libraryButton.heightAnchor constraintEqualToConstant:44],

        // Blur fills the button
        [blurView.topAnchor constraintEqualToAnchor:libraryButton.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:libraryButton.bottomAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:libraryButton.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:libraryButton.trailingAnchor],
    ]];

    [libraryButton addTarget:self
                       action:@selector(sc_openPhotoLibrary)
             forControlEvents:UIControlEventTouchUpInside];
}

// --- Photo picker presentation ---
%new
- (void)sc_openPhotoLibrary {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 1;
    config.filter = [PHPickerFilter imagesFilter];

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];

    // Create and retain the delegate via an associated object
    SCIInstantsPickerDelegate *pickerDelegate =
        [[SCIInstantsPickerDelegate alloc] initWithCameraViewController:self];
    objc_setAssociatedObject(self, &kSCIPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    picker.delegate = pickerDelegate;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;

    [self presentViewController:picker animated:YES completion:nil];
}

%end


// ---------------------------------------------------------------------------
// Discovery hook: log every VC that looks Quicksnap/Camera-related
// This runs on ALL view controllers — helps find the real class name.
// Remove once the correct class is identified.
// ---------------------------------------------------------------------------

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    NSString *className = NSStringFromClass([self class]);
    NSString *lower = [className lowercaseString];

    if ([lower containsString:@"quicksnap"] ||
        [lower containsString:@"instant"] ||
        ([lower containsString:@"camera"] && ![lower containsString:@"permission"])) {
        os_log(OS_LOG_DEFAULT, "[SCInsta] FOUND VC: %{public}s", className.UTF8String);

        // Also dump methods to help find the capture selector
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList([self class], &methodCount);
        os_log(OS_LOG_DEFAULT, "[SCInsta] %{public}s has %u methods:", className.UTF8String, methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            os_log(OS_LOG_DEFAULT, "[SCInsta]   -> %{public}s", NSStringFromSelector(sel).UTF8String);
        }
        free(methods);
    }
}

%end


%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id)delegate {
    %orig;
    os_log(OS_LOG_DEFAULT, "[SCInsta] 📸 REAL PHOTO CAPTURED BY AVFOUNDATION!");
    os_log(OS_LOG_DEFAULT, "[SCInsta]   -> Delegate Class: %{public}s", class_getName([delegate class]));
    
    // Dump methods of the delegate class to see what Instagram uses
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList([delegate class], &methodCount);
    os_log(OS_LOG_DEFAULT, "[SCInsta]   -> Delegate has %u methods:", methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        SEL sel = method_getName(methods[i]);
        os_log(OS_LOG_DEFAULT, "[SCInsta]      -> %{public}s", NSStringFromSelector(sel).UTF8String);
    }
    free(methods);
}

%end


// ---------------------------------------------------------------------------
// Constructor — log that the hook loaded
// ---------------------------------------------------------------------------
%ctor {
    NSLog(@"[SCInsta] InstantsCameraRoll hook loaded");
}

