// This is a simplified IPFS client for the browser
// In a production environment, you would use a more robust solution

import { create } from "ipfs-http-client"

// Configure IPFS client to use a public gateway or your own node
// For this example, we'll use a public gateway
const ipfs = create({ url: "https://ipfs.infura.io:5001/api/v0" })

/**
 * Uploads content to IPFS
 * @param content Content to upload (string, Buffer, or Blob)
 * @returns CID (Content Identifier) of the uploaded content
 */
export async function uploadToIPFS(content: string | Buffer | Blob): Promise<string> {
  try {
    // Convert content to appropriate format if needed
    let data = content
    if (typeof content === "string") {
      data = new TextEncoder().encode(content)
    } else if (content instanceof Blob) {
      data = await content.arrayBuffer()
    }

    // Add content to IPFS
    const result = await ipfs.add(data)
    return result.cid.toString()
  } catch (error) {
    console.error("Error uploading to IPFS:", error)
    throw new Error("Failed to upload content to IPFS")
  }
}

/**
 * Retrieves content from IPFS by its CID
 * @param cid Content Identifier
 * @returns Content as a string
 */
export async function getFromIPFS(cid: string): Promise<string> {
  try {
    const chunks = []
    for await (const chunk of ipfs.cat(cid)) {
      chunks.push(chunk)
    }

    // Combine chunks and convert to string
    const content = new TextDecoder().decode(
      chunks.reduce((prev, curr) => {
        const merged = new Uint8Array(prev.length + curr.length)
        merged.set(prev)
        merged.set(curr, prev.length)
        return merged
      }, new Uint8Array(0)),
    )

    return content
  } catch (error) {
    console.error("Error retrieving from IPFS:", error)
    throw new Error("Failed to retrieve content from IPFS")
  }
}

