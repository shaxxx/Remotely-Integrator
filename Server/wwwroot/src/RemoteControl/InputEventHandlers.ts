import {
    AudioButton,
    ChangeScreenButton,
    HorizontalBars,
    ScreenSelectBar,
    ClipboardTransferButton,
    ClipboardTransferBar,
    TypeClipboardButton,
    ConnectButton,
    CtrlAltDelButton,
    DisconnectButton,
    FileTransferButton,
    FileTransferInput,
    FitToScreenButton,
    ScreenViewer,
    BlockInputButton,
    InviteButton,
    KeyboardButton,
    TouchKeyboardInput,
    MenuFrame,
    MenuButton,
    ScreenViewerWrapper,
    WindowsSessionSelect,
    RecordSessionButton,
    DownloadRecordingButton,
    VideoScreenViewer,
    StreamVideoButton,
    FileTransferBar,
    FileUploadButtton,
    FileDownloadButton,
    UpdateStreamingToggled,
    ViewOnlyButton,
    FullScreenButton
} from "./UI.js";
import { Sound } from "./Sound.js";
import { ViewerApp } from "./App.js";
import { Point } from "./Models/Point.js";
import { UploadFiles } from "./FileTransferService.js";
import { RemoteControlMode } from "./Enums/RemoteControlMode.js";
import { GetDistanceBetween } from "./Utilities.js";
import { ShowMessage } from "./UI.js";
import { SetSettings } from "./SettingsService.js";

var isDragging: boolean;
var currentPointerDevice: string;
var currentTouchCount: number;
var cancelNextViewerClick: boolean;
var isPinchZooming: boolean;
var startPinchPoint1: Point;
var startPinchPoint2: Point;
var lastPinchDistance: number;
var isMenuButtonDragging: boolean;
var startMenuDraggingY: number;
// Long-press na dodir (iz immense/RemoteControl): preglednik sam okida "contextmenu" nakon
// dugog dodira; pomak veći od LongPressMoveTolerance piksela pretvara ga u povlačenje.
const LongPressMoveTolerance = 5;
// iOS Safari ne okida "contextmenu" na dugi dodir, pa isto stanje ulazimo vlastitim timerom.
const LongPressFallbackMs = 700;
var longPressFallbackTimeout: number = -1;
var fallbackStartClientX: number;
var fallbackStartClientY: number;
var longPressStarted: boolean;
var longPressStartX: number;
var longPressStartY: number;
var lastDragPercentX: number;
var lastDragPercentY: number;
var lastPinchCenterX: number;
var lastPinchCenterY: number;
var isScrolling: boolean;
var lastScrollTime: number;
var lastScrollTouchY1: number;
var lastScrollTouchY2: number;

export function ApplyInputHandlers() {
    AudioButton.addEventListener("click", (ev) => {
        AudioButton.classList.toggle("toggled");
        var toggleOn = AudioButton.classList.contains("toggled");
        if (toggleOn) {
            Sound.Init();
        }
        ViewerApp.MessageSender.SendToggleAudio(toggleOn);
    });
    ChangeScreenButton.addEventListener("click", (ev) => {
        closeAllHorizontalBars("screenSelectBar");
        ScreenSelectBar.classList.toggle("open");
    });
    ClipboardTransferButton.addEventListener("click", (ev) => {
        closeAllHorizontalBars("clipboardTransferBar");
        ClipboardTransferBar.classList.toggle("open");
    });
    ViewOnlyButton.addEventListener("click", () => {
        ViewOnlyButton.classList.toggle("toggled");
        ViewerApp.ViewOnlyMode = ViewOnlyButton.classList.contains("toggled");
    });
    TypeClipboardButton.addEventListener("click", (ev) => {
        if (!location.protocol.includes("https") &&
            !location.origin.includes("localhost")) {
            alert("Clipboard API only works on HTTPS or localhost.");
        }

        if (!navigator.clipboard?.readText) {
            alert("Clipboard access isn't supported on this browser.");
            return;
        }

        if (ViewerApp.ViewOnlyMode) {
            alert("View-only mode is enabled.");
            return;
        }

        navigator.clipboard.readText().then(text => {
            sendTypedText(text, false);
            ShowMessage("Clipboard sent!");
        }, reason => {
            alert("Unable to read clipboard.  Please check your permissions.");
            console.log("Unable to read clipboard.  Reason: " + reason);
        });
    });
    ConnectButton.addEventListener("click", (ev) => {
        ViewerApp.ConnectToClient();
    });
    CtrlAltDelButton.addEventListener("click", (ev) => {
        if (!ViewerApp.ServiceID) {
            ShowMessage("Not available for this session.");
            return;
        }

        if (ViewerApp.ViewOnlyMode) {
            alert("View-only mode is enabled.");
            return;
        }

        closeAllHorizontalBars(null);
        ViewerApp.MessageSender.SendCtrlAltDel();
    });
    DisconnectButton.addEventListener("click", (ev) => {
        ConnectButton.removeAttribute("disabled");
        ViewerApp.ViewerHubConnection.Connection.stop();
        if (location.search.includes("fromApi=true")) {
            window.close();
        }
    });
    document.querySelectorAll("#sessionIDInput, #nameInput").forEach(x => {
        x.addEventListener("keypress", (ev: KeyboardEvent) => {
            if (ev.key.toLowerCase() == "enter") {
                ViewerApp.ConnectToClient();
            }
        })
    });
    FileTransferButton.addEventListener("click", (ev) => {
        closeAllHorizontalBars(FileTransferBar.id);
        FileTransferBar.classList.toggle("open");
    });
    FileUploadButtton.addEventListener("click", (ev) => {
        FileTransferInput.click();
    });
    FileDownloadButton.addEventListener("click", (ev) => {
        if (ViewerApp.ViewOnlyMode) {
            alert("View-only mode is enabled.");
            return;
        }

        ViewerApp.MessageSender.SendOpenFileTransferWindow();
    });
    FileTransferInput.addEventListener("change", (ev) => {
        UploadFiles(FileTransferInput.files);
    });
    FitToScreenButton.addEventListener("click", (ev) => {
        FitToScreenButton.classList.toggle("toggled");
        if (FitToScreenButton.classList.contains("toggled")) {
            ScreenViewer.style.removeProperty("max-width");
            ScreenViewer.style.removeProperty("max-height");
            VideoScreenViewer.style.removeProperty("max-width");
            VideoScreenViewer.style.removeProperty("max-height");
        }
        else {
            ScreenViewer.style.maxWidth = "unset";
            ScreenViewer.style.maxHeight = "unset";
            VideoScreenViewer.style.maxWidth = "unset";
            VideoScreenViewer.style.maxHeight = "unset";
        }
    });
    FullScreenButton.addEventListener("click", () => {
        document.body.requestFullscreen();
    })
    BlockInputButton.addEventListener("click", (ev) => {
        if (ViewerApp.ViewOnlyMode) {
            alert("View-only mode is enabled.");
            return;
        }
        BlockInputButton.classList.toggle("toggled");
        if (BlockInputButton.classList.contains("toggled")) {
            ViewerApp.MessageSender.SendToggleBlockInput(true);
        }
        else {
            ViewerApp.MessageSender.SendToggleBlockInput(false);
        }
    });
    InviteButton.addEventListener("click", (ev) => {
        var url = "";
        if (ViewerApp.Mode == RemoteControlMode.Normal) {
            url = `${location.origin}${location.pathname}?sessionID=${ViewerApp.CasterID}`;
        }
        else {
            url = `${location.origin}${location.pathname}?casterID=${ViewerApp.CasterID}&serviceID=${ViewerApp.ServiceID}`;
        }
        ViewerApp.ClipboardWatcher.SetClipboardText(url);
        ShowMessage("Link copied to clipboard.");
    });
    KeyboardButton.addEventListener("click", (ev) => {
        closeAllHorizontalBars(null);
        KeyboardButton.classList.toggle("toggled");
        if (KeyboardButton.classList.contains("toggled")) {
            TouchKeyboardInput.focus();
        }
        else {
            TouchKeyboardInput.blur();
        }
        MenuFrame.classList.remove("open");
        MenuButton.classList.remove("open");
    });
    MenuButton.addEventListener("click", (ev) => {
        if (isMenuButtonDragging) {
            isMenuButtonDragging = false;
            return;
        }
        MenuFrame.classList.toggle("open");
        MenuButton.classList.toggle("open");
        closeAllHorizontalBars(null);
    });
    MenuButton.addEventListener("mousedown", (ev) => {
        isMenuButtonDragging = false;
        startMenuDraggingY = ev.clientY;
        window.addEventListener("mousemove", moveMenuButton);
        window.addEventListener("mouseup", removeMouseButtonWindowListeners);
        window.addEventListener("mouseleave", removeMouseButtonWindowListeners);
    });
    MenuButton.addEventListener("touchmove", (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        MenuButton.style.top = `${ev.touches[0].clientY}px`;
    });
    StreamVideoButton.addEventListener("click", (ev) => {
        var toggleOn = !StreamVideoButton.classList.contains("toggled");

        ViewerApp.Settings.streamModeEnabled = toggleOn;
        SetSettings(ViewerApp.Settings);

        UpdateStreamingToggled(toggleOn);
        ViewerApp.MessageSender.SendToggleWebRtcVideo(toggleOn);
    });

    [ ScreenViewer, VideoScreenViewer ].forEach(viewer => {
        viewer.addEventListener("pointermove", function (e: PointerEvent) {
            currentPointerDevice = e.pointerType;
        });

        viewer.addEventListener("pointerdown", function (e: PointerEvent) {
            currentPointerDevice = e.pointerType;
        });

        viewer.addEventListener("pointerenter", function (e: PointerEvent) {
            currentPointerDevice = e.pointerType;
        });

        viewer.addEventListener("mousemove", function (e: MouseEvent) {
            e.preventDefault();

            if (ViewerApp.ViewOnlyMode) {
                return;
            }

            var percentX = e.offsetX / viewer.clientWidth;
            var percentY = e.offsetY / viewer.clientHeight;
            ViewerApp.MessageSender.SendMouseMove(percentX, percentY);
        });


        viewer.addEventListener("mousedown", function (e: MouseEvent) {
            if (currentPointerDevice == "touch") {
                return;
            }

            e.preventDefault();

            if (ViewerApp.ViewOnlyMode) {
                return;
            }

            var percentX = e.offsetX / viewer.clientWidth;
            var percentY = e.offsetY / viewer.clientHeight;
            ViewerApp.MessageSender.SendMouseDown(e.button, percentX, percentY);
        });

        viewer.addEventListener("mouseup", function (e: MouseEvent) {
            if (currentPointerDevice == "touch") {
                return;
            }
            if (e.button != 0 && e.button != 2) {
                return;
            }
            e.preventDefault();

            if (ViewerApp.ViewOnlyMode) {
                return;
            }

            var percentX = e.offsetX / viewer.clientWidth;
            var percentY = e.offsetY / viewer.clientHeight;
            ViewerApp.MessageSender.SendMouseUp(e.button, percentX, percentY);
        });

        viewer.addEventListener("click", function (e: MouseEvent) {
            if (cancelNextViewerClick) {
                cancelNextViewerClick = false;
                return;
            }
            if (currentPointerDevice == "mouse") {
                e.preventDefault();
                e.stopPropagation();
            }
            else if (currentPointerDevice == "touch" && currentTouchCount == 0) {
                if (ViewerApp.ViewOnlyMode) {
                    return;
                }

                var percentX = e.offsetX / viewer.clientWidth;
                var percentY = e.offsetY / viewer.clientHeight;
                ViewerApp.MessageSender.SendTap(percentX, percentY);
            }
        });

        viewer.addEventListener("touchstart", function (e: TouchEvent) {
            currentTouchCount = e.touches.length;

            if (currentTouchCount > 1) {
                cancelNextViewerClick = true;

                // Drugi prst prekida long-press / povlačenje; ako je tipka pritisnuta, pusti je.
                cancelLongPressFallback();
                releaseDragIfNeeded(lastDragPercentX, lastDragPercentY);
                longPressStarted = false;
                isDragging = false;
            }
            else if (currentTouchCount == 1) {
                // Svaki novi dodir jednim prstom počinje čisto.
                cancelLongPressFallback();
                releaseDragIfNeeded(lastDragPercentX, lastDragPercentY);
                longPressStarted = false;
                isDragging = false;

                if (!ViewerApp.ViewOnlyMode) {
                    fallbackStartClientX = e.touches[0].clientX;
                    fallbackStartClientY = e.touches[0].clientY;
                    longPressFallbackTimeout = window.setTimeout(() => {
                        longPressFallbackTimeout = -1;
                        enterLongPress(viewer, fallbackStartClientX, fallbackStartClientY);
                    }, LongPressFallbackMs);
                }
            }
            if (currentTouchCount == 2) {
                lastScrollTouchY1 = e.touches[0].pageY;
                lastScrollTouchY2 = e.touches[1].pageY;
                startPinchPoint1 = { X: e.touches[0].pageX, Y: e.touches[0].pageY, IsEmpty: false };
                startPinchPoint2 = { X: e.touches[1].pageX, Y: e.touches[1].pageY, IsEmpty: false };
                lastPinchDistance = GetDistanceBetween(startPinchPoint1.X,
                    startPinchPoint1.Y,
                    startPinchPoint2.X,
                    startPinchPoint2.Y);
                lastPinchCenterX = (startPinchPoint1.X + startPinchPoint2.X) / 2;
                lastPinchCenterY = (startPinchPoint1.Y + startPinchPoint2.Y) / 2;
            }
            isDragging = false;
            KeyboardButton.removeAttribute("hidden");
            var focusedInput = document.querySelector("input:focus") as HTMLInputElement;
            if (focusedInput) {
                focusedInput.blur();
            }
        });


        viewer.addEventListener("touchmove", function (e: TouchEvent) {
            currentTouchCount = e.touches.length;

            if (longPressFallbackTimeout > -1 &&
                (e.touches.length != 1 ||
                    GetDistanceBetween(fallbackStartClientX, fallbackStartClientY,
                        e.touches[0].clientX, e.touches[0].clientY) > LongPressMoveTolerance)) {
                cancelLongPressFallback();
            }

            if (longPressStarted || isDragging) {
                e.preventDefault();
            }

            if (e.touches.length == 1 && longPressStarted && !isDragging) {
                e.stopPropagation();

                if (ViewerApp.ViewOnlyMode) {
                    return;
                }

                const rect = viewer.getBoundingClientRect();
                const moveDistance = GetDistanceBetween(
                    longPressStartX,
                    longPressStartY,
                    e.touches[0].clientX - rect.left,
                    e.touches[0].clientY - rect.top);

                if (moveDistance > LongPressMoveTolerance) {
                    // Klik-i-povuci: počni od točke početnog dodira.
                    isDragging = true;
                    lastDragPercentX = longPressStartX / viewer.clientWidth;
                    lastDragPercentY = longPressStartY / viewer.clientHeight;
                    ViewerApp.MessageSender.SendMouseMove(lastDragPercentX, lastDragPercentY);
                    ViewerApp.MessageSender.SendMouseDown(0, lastDragPercentX, lastDragPercentY);
                }
                return;
            }

            if (e.touches.length == 2) {
                let touchMove1 = lastScrollTouchY1 - e.touches[0].pageY;
                let touchMove2 = lastScrollTouchY2 - e.touches[1].pageY;

                if (!isPinchZooming && (isScrolling || touchMove1 * touchMove2 > 0)) {
                    // Both touch points are moving in the same direction.  We're doing a scroll.

                    if (ViewerApp.ViewOnlyMode) {
                        // View-only: ni pomak miša ni kotačić.
                        isScrolling = true;
                        return;
                    }

                    if (!isScrolling) {
                        // If this is the start of scrolling, move the mouse to our touch point so
                        // the scroll wheel action will target the intended element on screen.
                        var screenViewerLeft = viewer.getBoundingClientRect().left;
                        var screenViewerTop = viewer.getBoundingClientRect().top;
                        var pagePercentX = (e.touches[0].clientX - screenViewerLeft) / viewer.clientWidth;
                        var pagePercentY = (e.touches[0].clientY - screenViewerTop) / viewer.clientHeight;
                        ViewerApp.MessageSender.SendMouseMove(pagePercentX, pagePercentY);
                    }

                    isScrolling = true;
                    if (Date.now() - lastScrollTime < 100) {
                        return;
                    }
                    lastScrollTime = Date.now();
                    let yMove = Math.max(-1, Math.min(touchMove1, 1));
                    ViewerApp.MessageSender.SendMouseWheel(0, yMove);
                    lastScrollTouchY1 = e.touches[0].pageY;
                    return;
                }


                var pinchPoint1 = {
                    X: e.touches[0].pageX,
                    Y: e.touches[0].pageY,
                    IsEmpty: false
                };
                var pinchPoint2 = {
                    X: e.touches[1].pageX,
                    Y: e.touches[1].pageY,
                    IsEmpty: false
                };
                var pinchDistance = GetDistanceBetween(pinchPoint1.X,
                    pinchPoint1.Y,
                    pinchPoint2.X,
                    pinchPoint2.Y);


                var pinchCenterX = (pinchPoint1.X + pinchPoint2.X) / 2;
                var pinchCenterY = (pinchPoint1.Y + pinchPoint2.Y) / 2;

                ScreenViewerWrapper.scrollBy(lastPinchCenterX - pinchCenterX,
                    lastPinchCenterY - pinchCenterY);

                lastPinchCenterX = pinchCenterX;
                lastPinchCenterY = pinchCenterY;

                if (Math.abs(pinchDistance - lastPinchDistance) > 5) {
                    isPinchZooming = true;
                    if (FitToScreenButton.classList.contains("toggled")) {
                        FitToScreenButton.click();
                    }

                    var currentWidth = viewer.clientWidth;
                    var currentHeight = viewer.clientHeight;

                    var clientAdjustedScrollLeftPercent = (ScreenViewerWrapper.scrollLeft + (ScreenViewerWrapper.clientWidth * .5)) / ScreenViewerWrapper.scrollWidth;
                    var clientAdjustedScrollTopPercent = (ScreenViewerWrapper.scrollTop + (ScreenViewerWrapper.clientHeight * .5)) / ScreenViewerWrapper.scrollHeight;

                    var currentWidthPercent = Number(viewer.style.width.slice(0, -1));
                    var newWidthPercent = Math.max(100, (currentWidthPercent + (pinchDistance - lastPinchDistance) * (currentWidthPercent / 100)));
                    newWidthPercent = Math.min(5000, newWidthPercent);
                    viewer.style.width = String(newWidthPercent) + "%";

                    var heightChange = viewer.clientHeight - currentHeight;
                    var widthChange = viewer.clientWidth - currentWidth;

                    var pinchAdjustX = pinchCenterX / window.innerWidth - .5;
                    var pinchAdjustY = pinchCenterY / window.innerHeight - .5;

                    var scrollByX = widthChange * (clientAdjustedScrollLeftPercent + (pinchAdjustX * ScreenViewerWrapper.clientWidth / ScreenViewerWrapper.scrollWidth));
                    var scrollByY = heightChange * (clientAdjustedScrollTopPercent + (pinchAdjustY * ScreenViewerWrapper.clientHeight / ScreenViewerWrapper.scrollHeight));

                    ScreenViewerWrapper.scrollBy(scrollByX, scrollByY);

                    lastPinchDistance = pinchDistance;
                }
                return;
            }
            else if (isDragging) {
                e.preventDefault();
                e.stopPropagation();

                if (ViewerApp.ViewOnlyMode) {
                    return;
                }

                var screenViewerLeft = viewer.getBoundingClientRect().left;
                var screenViewerTop = viewer.getBoundingClientRect().top;
                var pagePercentX = (e.touches[0].clientX - screenViewerLeft) / viewer.clientWidth;
                var pagePercentY = (e.touches[0].clientY - screenViewerTop) / viewer.clientHeight;
                lastDragPercentX = pagePercentX;
                lastDragPercentY = pagePercentY;
                ViewerApp.MessageSender.SendMouseMove(pagePercentX, pagePercentY);
            }
        });

        viewer.addEventListener("touchend", function (e: TouchEvent) {
            currentTouchCount = e.touches.length;
            cancelLongPressFallback();

            if (currentTouchCount == 0) {
                cancelNextViewerClick = false;
                isPinchZooming = false;
                isScrolling = false;
                lastScrollTouchY1 = null;
                lastScrollTouchY2 = null;
                startPinchPoint1 = null;
                startPinchPoint2 = null;
            }

            var rect = viewer.getBoundingClientRect();
            var percentX = (e.changedTouches[0].clientX - rect.left) / viewer.clientWidth;
            var percentY = (e.changedTouches[0].clientY - rect.top) / viewer.clientHeight;

            if (longPressStarted && !isDragging && !ViewerApp.ViewOnlyMode) {
                // Long-press na mjestu: desni klik (miš je već pomaknut u contextmenu).
                ViewerApp.MessageSender.SendMouseDown(2, percentX, percentY);
                ViewerApp.MessageSender.SendMouseUp(2, percentX, percentY);
            }

            // Puštanje tipke i kad je view-only uključen usred povlačenja.
            releaseDragIfNeeded(percentX, percentY);

            longPressStarted = false;
            isDragging = false;
        });

        viewer.addEventListener("touchcancel", function (e: TouchEvent) {
            currentTouchCount = e.touches.length;
            resetTouchState();
        });


        viewer.addEventListener("contextmenu", (ev: MouseEvent) => {
            ev.preventDefault();

            if (currentPointerDevice == "touch") {
                enterLongPress(viewer, ev.clientX, ev.clientY);
            }
        });

        viewer.addEventListener("wheel", function (e: WheelEvent) {
            e.preventDefault();
            if (ViewerApp.ViewOnlyMode) {
                return;
            }
            ViewerApp.MessageSender.SendMouseWheel(e.deltaX, e.deltaY);
        });

    });


    // Hidden touch-keyboard input.
    //
    // The field always holds one invisible placeholder (zero-width space) with the
    // caret after it.  Browsers fire no beforeinput/input when Backspace is pressed
    // in an empty field, so deleting the placeholder is itself the signal for
    // "Backspace on the remote computer"; the placeholder is then restored.
    // Real text is the field value minus the placeholder; the placeholder is never sent.
    //
    // One Backspace/Enter per physical key.  Up to three events can describe the
    // same key press: keydown (key or keyCode 8/13), beforeinput
    // (deleteContentBackward / insertLineBreak) and, for Backspace, the input event
    // that reports the placeholder missing.  Whichever comes first sends through
    // sendTouchKey(); keydown records it in keydownSent so the later events for
    // that same press are swallowed (consumed once).  keyup or a 500 ms timer
    // (cancelled whenever a new key press arrives) clears the record.
    const Sentinel = "\u200b";
    let keydownSent: "Backspace" | "Enter" | null = null;
    let keydownTimer = 0;
    let isTouchComposing = false;

    const resetTouchField = () => {
        TouchKeyboardInput.value = Sentinel;
        TouchKeyboardInput.setSelectionRange(Sentinel.length, Sentinel.length);
    };
    const stripSentinel = (value: string) => (value || "").split(Sentinel).join("");
    const fieldText = () => stripSentinel(TouchKeyboardInput.value);

    const sendTouchKey = (key: "Backspace" | "Enter") => {
        if (ViewerApp.ViewOnlyMode) {
            return;
        }
        ViewerApp.MessageSender.SendKeyPress(key);
    };

    // Returns true (and clears the record) if keydown already sent this key.
    const consumeKeydownSent = (key: "Backspace" | "Enter") => {
        if (keydownSent !== key) {
            return false;
        }
        keydownSent = null;
        window.clearTimeout(keydownTimer);
        return true;
    };

    // SendKeys on the desktop treats these characters as commands; braces make them literal.
    const escapeSendKeys = (text: string) => text.replace(/[+^%~(){}[\]]/g, "{$&}");

    // The desktop types the text with SendKeys, which leaves a hook on its input thread.
    // The next input action then fails the desktop switch and is dropped while the
    // thread is replaced, so a Shift action follows the text to absorb that drop; when
    // it does run it is harmless.  SendKeys also releases Shift on the remote computer,
    // so while the user holds Shift it is pressed again (twice, the first may be dropped).
    const sendTypedText = (text: string, shiftHeld: boolean) => {
        ViewerApp.MessageSender.SendClipboardTransfer(escapeSendKeys(text), true);
        if (shiftHeld) {
            ViewerApp.MessageSender.SendKeyDown("Shift");
            ViewerApp.MessageSender.SendKeyDown("Shift");
        }
        else {
            ViewerApp.MessageSender.SendKeyUp("Shift");
        }
    };

    const flushTouchText = (text: string) => {
        resetTouchField();
        if (ViewerApp.ViewOnlyMode || !text) {
            return;
        }
        sendTypedText(text, false);
    };

    resetTouchField();

    TouchKeyboardInput.addEventListener("focus", () => {
        if (!TouchKeyboardInput.value.includes(Sentinel)) {
            resetTouchField();
        }
        else {
            TouchKeyboardInput.setSelectionRange(TouchKeyboardInput.value.length, TouchKeyboardInput.value.length);
        }
    });

    TouchKeyboardInput.addEventListener("keydown", (ev) => {
        const unidentified = ev.key === "Unidentified" || ev.keyCode === 229;
        let key: "Backspace" | "Enter" | null = null;
        if (ev.key === "Backspace" || (unidentified && ev.keyCode === 8)) {
            key = "Backspace";
        }
        else if (ev.key === "Enter" || (unidentified && ev.keyCode === 13)) {
            key = "Enter";
        }
        if (!key || ev.isComposing || isTouchComposing) {
            return;
        }
        if (key === "Backspace" && fieldText().length > 0) {
            return;
        }
        ev.preventDefault();
        keydownSent = key;
        window.clearTimeout(keydownTimer);
        keydownTimer = window.setTimeout(() => keydownSent = null, 500);
        sendTouchKey(key);
    });

    TouchKeyboardInput.addEventListener("keyup", () => {
        keydownSent = null;
        window.clearTimeout(keydownTimer);
    });

    TouchKeyboardInput.addEventListener("beforeinput", (ev: InputEvent) => {
        const composing = ev.isComposing || isTouchComposing;
        if (ev.inputType === "deleteContentBackward") {
            // Backspace while composing, or with text in the field, edits the
            // local text.  Only a Backspace that would delete the placeholder
            // goes to the remote computer.
            if (composing || fieldText().length > 0) {
                return;
            }
            ev.preventDefault();
            if (consumeKeydownSent("Backspace")) {
                return;
            }
            sendTouchKey("Backspace");
            return;
        }

        if (ev.inputType === "insertLineBreak" || ev.inputType === "insertParagraph") {
            ev.preventDefault();
            if (composing) {
                // Text committed together with a line break: send the composed
                // text first, then Enter.  With nothing composed, ignore it.
                const text = fieldText();
                isTouchComposing = false;
                if (!text) {
                    return;
                }
                flushTouchText(text);
                sendTouchKey("Enter");
                return;
            }
            if (consumeKeydownSent("Enter")) {
                return;
            }
            sendTouchKey("Enter");
        }
    });

    TouchKeyboardInput.addEventListener("compositionstart", () => {
        isTouchComposing = true;
    });

    TouchKeyboardInput.addEventListener("compositionend", (ev: CompositionEvent) => {
        isTouchComposing = false;
        // Exactly one source for the text: the field value if it has any, else
        // ev.data.  Flushing resets the field, so a later non-composing input
        // event sees only the placeholder and sends nothing.
        const fromField = fieldText();
        const text = fromField !== "" ? fromField : stripSentinel(ev.data);
        flushTouchText(text);
    });

    TouchKeyboardInput.addEventListener("input", (ev) => {
        if ((ev as InputEvent).isComposing || isTouchComposing) {
            return;
        }
        const value = TouchKeyboardInput.value;
        const text = stripSentinel(value);
        if (text === "" && value.includes(Sentinel)) {
            // Only the placeholder: nothing to send.
            TouchKeyboardInput.setSelectionRange(value.length, value.length);
            return;
        }
        if (text === "") {
            // The placeholder was deleted: Backspace, unless keydown/beforeinput sent it.
            if (!consumeKeydownSent("Backspace")) {
                sendTouchKey("Backspace");
            }
            resetTouchField();
            return;
        }
        flushTouchText(text);
    });

    TouchKeyboardInput.addEventListener("blur", (ev: FocusEvent) => {
        // The keyboard stays open until the toggle button is pressed again.
        if (!KeyboardButton.classList.contains("toggled")) {
            return;
        }
        // relatedTarget is null on iOS Safari when a <select> is tapped, so look at
        // the active element on the next tick before taking focus back.
        window.setTimeout(() => {
            if (!KeyboardButton.classList.contains("toggled")) {
                return;
            }
            const active = document.activeElement as HTMLElement;
            if (active && active !== TouchKeyboardInput &&
                /^(INPUT|SELECT|TEXTAREA)$/.test(active.tagName)) {
                return;
            }
            TouchKeyboardInput.focus();
        }, 0);
    });

    WindowsSessionSelect.addEventListener("focus", () => {
        ViewerApp.MessageSender.GetWindowsSessions();
    });
    WindowsSessionSelect.addEventListener("change", () => {
        ShowMessage("Switching sessions...");
        ViewerApp.MessageSender.ChangeWindowsSession(Number(WindowsSessionSelect.selectedOptions[0].value));
    });
    RecordSessionButton.addEventListener("click", () => {
        RecordSessionButton.classList.toggle("toggled");
        if (RecordSessionButton.classList.contains("toggled")) {
            RecordSessionButton.innerHTML = `Stop <i class="fas fa-record-vinyl">`;
            ViewerApp.SessionRecorder.Start();
        }
        else {
            RecordSessionButton.innerHTML = `Start <i class="fas fa-record-vinyl">`;
            ViewerApp.SessionRecorder.Stop();
        }
    });
    DownloadRecordingButton.addEventListener("click", () => {
        ViewerApp.SessionRecorder.DownloadVideo();
    });

    // The desktop's key path converts a character to the remote computer's ANSI code
    // page, so on Western European Windows č and ć arrive as c and đ as d, and it cannot
    // type AltGr characters (@, €, { on the Croatian layout) at all.  Those characters
    // are typed as text instead, and keysTypedAsText holds the codes of keys whose last
    // press went as text, so that their key-ups are not sent.
    const keysTypedAsText = new Set<string>();
    const isTypedAsText = (e: KeyboardEvent) => {
        if (e.key.length !== 1 || e.metaKey) {
            return false;
        }
        // AltGr arrives as Ctrl+Alt (Chrome) or as the AltGraph modifier (Firefox);
        // with a letter, digit or space it is a shortcut.
        if (e.getModifierState("AltGraph") || (e.ctrlKey && e.altKey)) {
            return !/[\sa-z0-9]/i.test(e.key);
        }
        if (e.ctrlKey || e.altKey) {
            return false;
        }
        return e.key.charCodeAt(0) > 0x7f;
    };
    // SendKeys types the case it is given and the remote Caps Lock then flips the letter,
    // so with Caps Lock on (assumed on for both computers) the case is flipped first.
    const caseForCapsLock = (e: KeyboardEvent) => {
        if (!e.getModifierState("CapsLock")) {
            return e.key;
        }
        const flipped = e.key === e.key.toUpperCase() ? e.key.toLowerCase() : e.key.toUpperCase();
        return flipped.length === 1 ? flipped : e.key;
    };

    window.addEventListener("keydown", function (e) {
        if (document.querySelector("input:focus") || document.querySelector("textarea:focus")) {
            return;
        }
        if (ViewerApp.ViewOnlyMode) {
            return;
        }
        if (!e.ctrlKey || !e.shiftKey || e.key.toLowerCase() != "i") {
            e.preventDefault();
        }
        // The desktop has no key for AltGraph.  Sending it only adds an input action,
        // and right after AltGr text that action makes the desktop drop the next key.
        if (e.key === "AltGraph") {
            return;
        }
        if (isTypedAsText(e)) {
            if (e.code) {
                keysTypedAsText.add(e.code);
            }
            sendTypedText(caseForCapsLock(e), e.shiftKey);
            return;
        }
        keysTypedAsText.delete(e.code);
        ViewerApp.MessageSender.SendKeyDown(e.key);
    });
    window.addEventListener("keyup", function (e) {
        if (document.querySelector("input:focus") || document.querySelector("textarea:focus")) {
            return;
        }
        e.preventDefault();
        if (ViewerApp.ViewOnlyMode) {
            return;
        }
        if (e.key === "AltGraph" || keysTypedAsText.delete(e.code)) {
            return;
        }
        ViewerApp.MessageSender.SendKeyUp(e.key);
    });

    window.addEventListener("blur", () => {
        keysTypedAsText.clear();
        resetTouchState();
        if (ViewerApp.ViewOnlyMode) {
            return;
        }
        ViewerApp.MessageSender.SendSetKeyStatesUp();
    });

    window.addEventListener("touchstart", () => {
        KeyboardButton.removeAttribute("hidden");
    });

    window.ondragover = function (e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
    };
    window.ondrop = function (e) {
        e.preventDefault();
        if (e.dataTransfer.files.length < 1) {
            return;
        }
        UploadFiles(e.dataTransfer.files);
    };
}

function closeAllHorizontalBars(exceptBarId: string) {
    HorizontalBars.forEach(x => {
        if (x.id != exceptBarId) {
            x.classList.remove('open');
        }
    })
}

function moveMenuButton(ev: MouseEvent) {
    if (Math.abs(ev.clientY - startMenuDraggingY) > 5) {
        if (ev.clientY < 0 || ev.clientY > window.innerHeight) {
            return;
        }
        isMenuButtonDragging = true;
        MenuButton.style.top = `${ev.clientY}px`;
    }
}

function removeMouseButtonWindowListeners(ev: MouseEvent) {
    window.removeEventListener("mousemove", moveMenuButton);
    window.removeEventListener("mouseup", removeMouseButtonWindowListeners);
    window.removeEventListener("mouseleave", removeMouseButtonWindowListeners);
}

function cancelLongPressFallback() {
    if (longPressFallbackTimeout > -1) {
        window.clearTimeout(longPressFallbackTimeout);
        longPressFallbackTimeout = -1;
    }
}

// Ulazak u stanje long-pressa (zajednički za "contextmenu" i iOS timer). Ne ulazi dvaput.
function enterLongPress(viewer: HTMLElement, clientX: number, clientY: number) {
    cancelLongPressFallback();
    if (longPressStarted || ViewerApp.ViewOnlyMode) {
        return;
    }
    // Početak desnog klika ili povlačenja: prvo pomakni miš na točku dodira.
    var rect = viewer.getBoundingClientRect();
    longPressStartX = clientX - rect.left;
    longPressStartY = clientY - rect.top;
    ViewerApp.MessageSender.SendMouseMove(longPressStartX / viewer.clientWidth, longPressStartY / viewer.clientHeight);
    longPressStarted = true;
}

// Puštanje pritisnute tipke je sigurnosna radnja: šalje se i ako je view-only uključen usred povlačenja.
function releaseDragIfNeeded(percentX: number, percentY: number) {
    if (isDragging) {
        ViewerApp.MessageSender.SendMouseUp(0, percentX, percentY);
    }
}

function resetTouchState() {
    cancelLongPressFallback();
    releaseDragIfNeeded(lastDragPercentX, lastDragPercentY);
    longPressStarted = false;
    isDragging = false;
    isScrolling = false;
    isPinchZooming = false;
}
