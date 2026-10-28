import { ViewerApp } from "./App.js";
import { Screen2DContext } from "./UI.js";
const BitmapQueue = [];
const ImagePartials = {};
let isProcessing = false;
let NextSequence = 0;
export function HandleCaptureReceived(captureFrame) {
    if (!ImagePartials[captureFrame.Sequence]) {
        ImagePartials[captureFrame.Sequence] = [];
    }
    ImagePartials[captureFrame.Sequence].push(captureFrame.ImageBytes);
    if (captureFrame.EndOfFrame) {
        var partials = ImagePartials[captureFrame.Sequence];
        let completedFrame = new Blob(partials);
        delete ImagePartials[captureFrame.Sequence];
        createImageBitmap(completedFrame).catch((ex) => {
            // Undecodable frame is still queued (not drawable), so it gets acked and the sequence advances.
            console.error(ex);
            return null;
        }).then(bitmap => {
            BitmapQueue.push({
                ImageContent: bitmap,
                FrameData: captureFrame
            });
            if (isProcessing) {
                return;
            }
            isProcessing = true;
            processQueue();
        });
        //let url = window.URL.createObjectURL(completedFrame);
        //let img = new Image(captureFrame.Width, captureFrame.Height);
        //img.onload = () => {
        //    UI.Screen2DContext.drawImage(img,
        //        captureFrame.Left,
        //        captureFrame.Top,
        //        captureFrame.Width,
        //        captureFrame.Height);
        //    window.URL.revokeObjectURL(url);
        //};
    }
}
// Processing is event-driven (promise callbacks) on purpose: timers are throttled to once
// per minute in hidden tabs, which delays the frame acks and makes the desktop end the session.
function processQueue() {
    try {
        if (BitmapQueue.length == 0) {
            isProcessing = false;
            return;
        }
        BitmapQueue.sort((a, b) => a.FrameData.Sequence - b.FrameData.Sequence);
        let completedFrame = BitmapQueue.shift();
        let content = completedFrame.ImageContent;
        let data = completedFrame.FrameData;
        if (data.Sequence == 0) {
            NextSequence = 0;
            BitmapQueue.splice(0).forEach(x => { var _a; return (_a = x.ImageContent) === null || _a === void 0 ? void 0 : _a.close(); });
        }
        if (data.Sequence < NextSequence) {
            // Stale frame: ack it anyway (an extra ack is harmless, a missing one is fatal), do not draw.
            content === null || content === void 0 ? void 0 : content.close();
            try {
                ViewerApp.MessageSender.SendFrameReceived();
            }
            catch (ex) {
                console.error(ex);
            }
            Promise.resolve().then(() => processQueue());
            return;
        }
        if (data.Sequence != NextSequence) {
            console.debug("Frame out of sequence.  Putting it back in queue.");
            BitmapQueue.push(completedFrame);
            // The next arriving frame restarts processing.
            isProcessing = false;
            return;
        }
        NextSequence = data.Sequence + 1;
        let drawn = content ?
            createImageBitmap(content).then(bitmap => {
                try {
                    Screen2DContext.drawImage(bitmap, data.Left, data.Top, data.Width, data.Height);
                }
                finally {
                    bitmap.close();
                    content.close();
                }
            }) :
            Promise.resolve();
        drawn.catch(ex => {
            content === null || content === void 0 ? void 0 : content.close();
            console.error(ex);
        }).then(() => {
            try {
                ViewerApp.MessageSender.SendFrameReceived();
            }
            catch (ex) {
                console.error(ex);
            }
            processQueue();
        });
    }
    catch (ex) {
        isProcessing = false;
        console.error(ex);
    }
}
//# sourceMappingURL=CaptureProcessor.js.map