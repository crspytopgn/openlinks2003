// The player creator's "face from a photo" in the browser: the player picks
// a photo (or takes one, on a phone), and MediaPipe's Face Landmarker finds
// the face's landmarks. Everything runs on the player's device: the photo is
// never uploaded or stored. Only MediaPipe's code and model are downloaded,
// from jsDelivr and Google's model storage (both Apache-2.0), the first time
// a face is looked for.
//
// Godot loads this file with JavaScriptBridge.eval and talks to it through
// window.olFace (see game/scripts/web/web_face_photo.gd).
(() => {
  if (window.olFace) return;

  const VERSION = "0.10.14";
  const CDN = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}`;
  const MODEL =
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";
  // Photos are scaled down to this many pixels on the long side.
  const MAX_SIDE = 1024;

  let canvas = null;
  let landmarker = null;

  async function loadLandmarker() {
    if (landmarker) return landmarker;
    const vision = await import(`${CDN}/vision_bundle.mjs`);
    const files = await vision.FilesetResolver.forVisionTasks(`${CDN}/wasm`);
    landmarker = await vision.FaceLandmarker.createFromOptions(files, {
      baseOptions: { modelAssetPath: MODEL, delegate: "CPU" },
      runningMode: "IMAGE",
      numFaces: 1,
    });
    return landmarker;
  }

  // Draws a picked image, the right way up and scaled down, on a canvas.
  async function draw(source) {
    const bitmap = await createImageBitmap(source, { imageOrientation: "from-image" });
    const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height));
    const c = document.createElement("canvas");
    c.width = Math.max(1, Math.round(bitmap.width * scale));
    c.height = Math.max(1, Math.round(bitmap.height * scale));
    c.getContext("2d").drawImage(bitmap, 0, 0, c.width, c.height);
    bitmap.close();
    canvas = c;
  }

  function jpegBase64() {
    return canvas.toDataURL("image/jpeg", 0.9).split(",")[1];
  }

  function chooseFile(camera) {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = "image/*";
      if (camera) input.capture = "user";
      input.style.display = "none";
      document.body.appendChild(input);
      let settled = false;
      const finish = (file) => {
        if (settled) return;
        settled = true;
        input.remove();
        resolve(file);
      };
      input.addEventListener("change", () => finish(input.files && input.files[0]));
      input.addEventListener("cancel", () => finish(null));
      input.click();
    });
  }

  window.olFace = {
    // pick(camera, doneCb): doneCb(ok, jsonOrError). The JSON holds the
    // scaled photo as base64 JPEG with its size; ok with "" if cancelled.
    pick(camera, doneCb) {
      (async () => {
        const file = await chooseFile(Boolean(camera));
        if (!file) return doneCb(true, "");
        await draw(file);
        doneCb(true, JSON.stringify({ width: canvas.width, height: canvas.height, jpeg: jpegBase64() }));
      })().catch((e) => doneCb(false, String((e && e.message) || e)));
    },

    // find(doneCb): doneCb(ok, jsonOrError) with every landmark of the face
    // in the last picked photo, in its pixels: {points: [x0, y0, x1, ...]},
    // or {points: []} if there is no face.
    find(doneCb) {
      (async () => {
        if (!canvas) throw new Error("no photo");
        const result = (await loadLandmarker()).detect(canvas);
        const face = result.faceLandmarks && result.faceLandmarks[0];
        const points = [];
        if (face) {
          for (const p of face) points.push(p.x * canvas.width, p.y * canvas.height);
        }
        doneCb(true, JSON.stringify({ points }));
      })().catch((e) => doneCb(false, String((e && e.message) || e)));
    },

    // Tests: use an image at a URL as the picked photo.
    useUrl(url, doneCb) {
      (async () => {
        const blob = await (await fetch(url)).blob();
        await draw(blob);
        doneCb(true, JSON.stringify({ width: canvas.width, height: canvas.height }));
      })().catch((e) => doneCb(false, String((e && e.message) || e)));
    },

    // Forgets the photo.
    clear() {
      canvas = null;
    },
  };
})();
