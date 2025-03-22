import { create } from "ipfs-http-client"
import { Web3Storage } from "web3.storage"

// Configure IPFS client
const ipfsClient = create({
  host: "ipfs.infura.io",
  port: 5001,
  protocol: "https",
  headers: {
    authorization: process.env.IPFS_AUTH || "",
  },
})

// Configure Web3.Storage client as a backup
const web3StorageClient = process.env.WEB3_STORAGE_TOKEN
  ? new Web3Storage({ token: process.env.WEB3_STORAGE_TOKEN })
  : null

/**
 * Uploads content to IPFS with redundancy
 * @param content Content to upload (string, Buffer, or Blob)
 * @returns CID (Content Identifier) of the uploaded content
 */
export async function uploadToDecentralizedStorage(content: string | Buffer | Blob): Promise<string> {
  try {
    // Convert content to appropriate format if needed
    let data = content
    if (typeof content === "string") {
      data = new TextEncoder().encode(content)
    } else if (content instanceof Blob) {
      data = await content.arrayBuffer()
    }

    // Try to upload to IPFS first
    try {
      const result = await ipfsClient.add(data as any)
      const cid = result.cid.toString()

      // Also upload to Web3.Storage for redundancy if available
      if (web3StorageClient) {
        const fileName = `${cid}.json`
        const file = new File([data as any], fileName, { type: "application/json" })
        await web3StorageClient.put([file], { name: fileName })
      }

      return cid
    } catch (ipfsError) {
      console.error("Error uploading to IPFS:", ipfsError)

      // Fallback to Web3.Storage if IPFS fails
      if (web3StorageClient) {
        const fileName = `${Date.now()}.json`
        const file = new File([data as any], fileName, { type: "application/json" })
        const cid = await web3StorageClient.put([file], { name: fileName })
        return cid
      }

      throw new Error("Failed to upload to decentralized storage")
    }
  } catch (error) {
    console.error("Error in decentralized storage upload:", error)
    throw new Error("Failed to upload content to decentralized storage")
  }
}

/**
 * Retrieves content from decentralized storage
 * @param cid Content Identifier
 * @returns Content as a string
 */
export async function getFromDecentralizedStorage(cid: string): Promise<string> {
  try {
    // Try to get from IPFS first
    try {
      const chunks = []
      for await (const chunk of ipfsClient.cat(cid)) {
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
    } catch (ipfsError) {
      console.error("Error retrieving from IPFS:", ipfsError)

      // Fallback to Web3.Storage if IPFS fails
      if (web3StorageClient) {
        const res = await fetch(`https://${cid}.ipfs.dweb.link`)
        if (!res.ok) {
          throw new Error(`Failed to fetch from Web3.Storage gateway: ${res.status}`)
        }
        return await res.text()
      }

      throw new Error("Failed to retrieve from decentralized storage")
    }
  } catch (error) {
    console.error("Error in decentralized storage retrieval:", error)
    throw new Error("Failed to retrieve content from decentralized storage")
  }
}

/**
 * Pins content to multiple IPFS pinning services for redundancy
 * @param cid Content Identifier to pin
 * @returns Array of pinning service responses
 */
export async function pinContent(cid: string): Promise<any[]> {
  const pinningServices = [
    // Pinata
    process.env.PINATA_API_KEY && process.env.PINATA_SECRET_API_KEY
      ? {
          name: "Pinata",
          pin: async () => {
            const res = await fetch("https://api.pinata.cloud/pinning/pinByHash", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                pinata_api_key: process.env.PINATA_API_KEY!,
                pinata_secret_api_key: process.env.PINATA_SECRET_API_KEY!,
              },
              body: JSON.stringify({
                hashToPin: cid,
                pinataMetadata: {
                  name: `DeNews-${cid}`,
                },
              }),
            })
            return await res.json()
          },
        }
      : null,

    // Infura (if using their IPFS service)
    process.env.INFURA_IPFS_PROJECT_ID && process.env.INFURA_IPFS_PROJECT_SECRET
      ? {
          name: "Infura",
          pin: async () => {
            // Infura pins automatically when you upload, but we can verify the pin
            const res = await fetch(`https://ipfs.infura.io:5001/api/v0/pin/ls?arg=${cid}`, {
              headers: {
                Authorization: `Basic ${Buffer.from(
                  `${process.env.INFURA_IPFS_PROJECT_ID}:${process.env.INFURA_IPFS_PROJECT_SECRET}`,
                ).toString("base64")}`,
              },
            })
            return await res.json()
          },
        }
      : null,
  ].filter(Boolean)

  const results = []

  for (const service of pinningServices) {
    if (service) {
      try {
        const result = await service.pin()
        results.push({
          service: service.name,
          success: true,
          result,
        })
      } catch (error) {
        console.error(`Error pinning to ${service.name}:`, error)
        results.push({
          service: service.name,
          success: false,
          error: (error as Error).message,
        })
      }
    }
  }

  return results
}

/**
 * Verifies content availability across multiple storage providers
 * @param cid Content Identifier to verify
 * @returns Availability status
 */
export async function verifyContentAvailability(cid: string): Promise<{
  available: boolean
  providers: { name: string; available: boolean }[]
}> {
  const providers = [
    { name: "IPFS Gateway", url: `https://ipfs.io/ipfs/${cid}` },
    { name: "Infura Gateway", url: `https://ipfs.infura.io/ipfs/${cid}` },
    { name: "Cloudflare Gateway", url: `https://cloudflare-ipfs.com/ipfs/${cid}` },
    { name: "Dweb Link", url: `https://${cid}.ipfs.dweb.link` },
  ]

  const results = await Promise.all(
    providers.map(async (provider) => {
      try {
        const res = await fetch(provider.url, { method: "HEAD" })
        return {
          name: provider.name,
          available: res.ok,
        }
      } catch (error) {
        console.error(`Error checking ${provider.name}:`, error)
        return {
          name: provider.name,
          available: false,
        }
      }
    }),
  )

  const anyAvailable = results.some((r) => r.available)

  return {
    available: anyAvailable,
    providers: results,
  }
}

