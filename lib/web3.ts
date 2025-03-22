import { ethers } from "ethers"
import DeNewsTokenABI from "@/contracts/abis/DeNewsToken.json"
import DeNewsContentABI from "@/contracts/abis/DeNewsContent.json"

// Contract addresses - these would be set after deployment
const TOKEN_CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000"
const CONTENT_CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000"

/**
 * Gets an ethers provider
 * @returns Ethers provider
 */
export function getProvider() {
  if (typeof window !== "undefined" && typeof window.ethereum !== "undefined") {
    return new ethers.BrowserProvider(window.ethereum)
  }

  // Fallback to a public provider
  return new ethers.JsonRpcProvider("https://mainnet.infura.io/v3/YOUR_INFURA_KEY")
}

/**
 * Gets the token contract instance
 * @param withSigner Whether to include a signer
 * @returns Contract instance
 */
export async function getTokenContract(withSigner = false) {
  const provider = getProvider()

  if (withSigner) {
    const signer = await provider.getSigner()
    return new ethers.Contract(TOKEN_CONTRACT_ADDRESS, DeNewsTokenABI, signer)
  }

  return new ethers.Contract(TOKEN_CONTRACT_ADDRESS, DeNewsTokenABI, provider)
}

/**
 * Gets the content contract instance
 * @param withSigner Whether to include a signer
 * @returns Contract instance
 */
export async function getContentContract(withSigner = false) {
  const provider = getProvider()

  if (withSigner) {
    const signer = await provider.getSigner()
    return new ethers.Contract(CONTENT_CONTRACT_ADDRESS, DeNewsContentABI, signer)
  }

  return new ethers.Contract(CONTENT_CONTRACT_ADDRESS, DeNewsContentABI, provider)
}

/**
 * Creates a new post on the blockchain
 * @param contentHash IPFS hash of the content
 * @param category Category of the post
 * @returns Transaction receipt
 */
export async function createPost(contentHash: string, category: string) {
  const contract = await getContentContract(true)
  const tx = await contract.createPost(contentHash, category)
  return await tx.wait()
}

/**
 * Likes a post
 * @param postId ID of the post to like
 * @returns Transaction receipt
 */
export async function likePost(postId: number) {
  const contract = await getContentContract(true)
  const tx = await contract.likePost(postId)
  return await tx.wait()
}

/**
 * Gets user reputation
 * @param address User address
 * @returns Reputation score
 */
export async function getUserReputation(address: string) {
  const contract = await getTokenContract()
  return await contract.getReputation(address)
}

/**
 * Gets posts by a user
 * @param address User address
 * @returns Array of post IDs
 */
export async function getPostsByUser(address: string) {
  const contract = await getContentContract()
  return await contract.getPostsByUser(address)
}

/**
 * Gets post details
 * @param postId Post ID
 * @returns Post details
 */
export async function getPostDetails(postId: number) {
  const contract = await getContentContract()
  return await contract.posts(postId)
}

