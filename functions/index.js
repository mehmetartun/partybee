/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/https");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const https = require("https");

initializeApp();
const db = getFirestore();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

exports.helloworld = onRequest((request, response) => {
    response.send("Hello World");
});

exports.writeTest = onRequest(async (request, response) => {
    try {
        const docRef = await db.collection("test").add({ name: "test" });
        response.send(`Document written with ID: ${docRef.id}`);
    } catch (error) {
        logger.error("Error writing to Firestore:", error);
        response.status(500).send(`Error: ${error.message}`);
    }
});

function downloadImage(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            if (res.statusCode !== 200) {
                reject(new Error(`Failed to download image: status code ${res.statusCode}`));
                return;
            }
            const chunks = [];
            res.on("data", (chunk) => chunks.push(chunk));
            res.on("end", () => resolve(Buffer.concat(chunks)));
            res.on("error", (err) => reject(err));
        }).on("error", (err) => reject(err));
    });
}

exports.characterizeRoom = onCall({ secrets: ["GEMINI_API_KEY"] }, async (request) => {
    const collectionPath = request.data.collectionPath || request.data.path;
    // const collectionPath = 'users/VCmciSPxQThVCuCyYrUl9hFwCHU2/parties/5lOUJK1kxMqMieGyxcwt/images';
    const prompt = request.data.prompt;
    if (!collectionPath) {
        throw new HttpsError("invalid-argument", "Missing 'collectionPath' or 'path' parameter.");
    }

    try {
        const snapshot = await db.collection(collectionPath).get();
        if (snapshot.empty) {
            throw new HttpsError("not-found", `No documents found in Firestore collection path: ${collectionPath}`);
        }

        const imageParts = [];

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const url = data.downloadUrl || data.imageUrl || data.url;
            const storagePath = data.storagePath;

            let buffer;
            let mimeType = "image/png";
            let resolvedName = "";

            try {
                if (storagePath) {
                    resolvedName = storagePath;
                    const bucket = getStorage().bucket();
                    const cleanPath = storagePath.startsWith("gs://")
                        ? storagePath.split("/").slice(3).join("/")
                        : storagePath;
                    const file = bucket.file(cleanPath);
                    const [downloadBuffer] = await file.download();
                    buffer = downloadBuffer;
                } else if (url) {
                    resolvedName = url;
                    buffer = await downloadImage(url);
                } else {
                    logger.warn(`Document ${doc.id} does not contain downloadUrl, imageUrl, url, or storagePath. Skipping.`);
                    continue;
                }

                // Determine MIME type
                const lowerName = resolvedName.toLowerCase();
                if (lowerName.endsWith(".jpg") || lowerName.endsWith(".jpeg")) {
                    mimeType = "image/jpeg";
                } else if (lowerName.endsWith(".webp")) {
                    mimeType = "image/webp";
                } else if (lowerName.endsWith(".gif")) {
                    mimeType = "image/gif";
                }

                imageParts.push({
                    inlineData: {
                        data: buffer.toString("base64"),
                        mimeType
                    }
                });
            } catch (imageErr) {
                logger.error(`Error downloading image for doc ${doc.id}:`, imageErr);
            }
        }

        if (imageParts.length === 0) {
            throw new HttpsError("failed-precondition", "No valid images could be successfully downloaded from the specified collection.");
        }

        // Initialize Gemini
        const apiKey = process.env.GEMINI_API_KEY;
        if (!apiKey) {
            logger.warn("GEMINI_API_KEY environment variable is not defined");
        }

        const genAI = new GoogleGenerativeAI(apiKey || "");
        const model = genAI.getGenerativeModel({ model: "gemini-3.5-flash" });


        const finalPrompt = prompt || "Characterize the room represented by these images. Analyze the dimensions, lighting, architecture, potential setup layouts, and overall vibe for hosting a party or event.";

        const result = await model.generateContent([finalPrompt, ...imageParts]);
        const responseText = result.response.text();

        return {
            text: responseText,
            markdown: responseText,
            success: true
        };
        // response.status(200).send(responseText);
    } catch (error) {
        logger.error("Error characterizing room from Firestore images:", error);
        if (error instanceof HttpsError) {
            throw error;
        }
        throw new HttpsError("internal", error.message || "An error occurred while characterizing the room.");
        // response.status(500).send(error.message);
    }
});

