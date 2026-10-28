import { ViewerApp } from "./App.js";
import { ShowMessage } from "./UI.js";

export class ClipboardWatcher {
    ClipboardTimer: number;
    LastClipboardText: string;
    NewClipboardText: string;
    private WarningShown = false;

    async WatchClipboard() {
        if (!location.protocol.includes("https") &&
            !location.origin.includes("localhost")) {
            console.warn("Clipboard API only works in a secure context (i.e. HTTPS or localhost).");
        }

        if (!navigator.clipboard?.readText) {
            console.warn("Clipboard API not supported.");
            this.WarnOnce();
            return;
        }

        if (this.ClipboardTimer) {
            console.log("ClipboardWatcher is already running.");
            return;
        }

        try {
            // This throws on Firefox, Safari, and possibly other browsers, which
            // only allow clipboard reads in response to a user action.
            await navigator.permissions.query({
                name: "clipboard-read" as PermissionName
            });
        }
        catch (ex) {
            console.error(ex);
            console.warn(
                "New restrictions have been placed on the Clipboard API in " +
                "some browsers that make it impossible to sync the clipboard " +
                "in the background.  You can read more about this topic here: " +
                "https://developer.mozilla.org/en-US/docs/Web/API/Clipboard_API#security_considerations");
            this.WarnOnce();
            return;
        }

        this.ClipboardTimer = window.setInterval(async () => {
            if (!document.hasFocus()) {
                return;
            }

            try {
                if (this.NewClipboardText && navigator.clipboard.writeText) {
                    await navigator.clipboard.writeText(this.NewClipboardText);
                    this.LastClipboardText = this.NewClipboardText;
                    this.NewClipboardText = null;
                    ShowMessage("Clipboard updated.");
                    return;
                }

                var newText = await navigator.clipboard.readText();
                if (this.LastClipboardText != newText) {
                    this.LastClipboardText = newText;
                    ViewerApp.MessageSender.SendClipboardTransfer(newText, false);
                }
            }
            catch (ex) {
                console.warn("Clipboard sync failed.", ex);
            }
        }, 500);
    }

    private WarnOnce() {
        const key = "remotely.clipboardWarningShown";
        try {
            if (localStorage.getItem(key)) {
                return;
            }
            localStorage.setItem(key, "true");
        }
        catch {
            // localStorage can throw (e.g. private mode).  Still warn once per page load.
            if (this.WarningShown) {
                return;
            }
        }
        this.WarningShown = true;
        alert("Clipboard sync is unavailable for this browser. Please see the console for details.");
    }

    SetClipboardText(text: string) {
        if (text == this.LastClipboardText) {
            return;
        }

        this.NewClipboardText = text;
    }
}