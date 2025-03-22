import { Pool } from "pg"

// Create a PostgreSQL connection pool using Neon.tech
// This is optional and can be replaced with any database solution
const pool = new Pool({
  host: process.env.POSTGRES_HOST || "localhost",
  port: Number.parseInt(process.env.POSTGRES_PORT || "5432"),
  database: process.env.POSTGRES_DATABASE || "denews",
  user: process.env.POSTGRES_USER || "postgres",
  password: process.env.POSTGRES_PASSWORD || "postgres",
  ssl:
    process.env.POSTGRES_SSL === "true"
      ? {
          rejectUnauthorized: false,
        }
      : undefined,
})

/**
 * Executes a SQL query
 * @param text SQL query text
 * @param params Query parameters
 * @returns Query result
 */
export async function query(text: string, params?: any[]) {
  try {
    const start = Date.now()
    const res = await pool.query(text, params)
    const duration = Date.now() - start
    console.log("Executed query", { text, duration, rows: res.rowCount })
    return res
  } catch (error) {
    console.error("Error executing query", error)
    throw error
  }
}

/**
 * Gets a user by wallet address
 * @param walletAddress Wallet address
 * @returns User object
 */
export async function getUserByWalletAddress(walletAddress: string) {
  const result = await query("SELECT * FROM users WHERE wallet_address = $1", [walletAddress])
  return result.rows[0]
}

/**
 * Creates a new user
 * @param walletAddress Wallet address
 * @param username Username
 * @param userType User type (individual, journalist, organization)
 * @returns Created user
 */
export async function createUser(walletAddress: string, username: string, userType: string) {
  const result = await query(
    "INSERT INTO users (wallet_address, username, user_type, reputation_score, created_at, updated_at) VALUES ($1, $2, $3, $4, NOW(), NOW()) RETURNING *",
    [walletAddress, username, userType, 0],
  )
  return result.rows[0]
}

/**
 * Gets posts with pagination
 * @param limit Number of posts to return
 * @param offset Offset for pagination
 * @returns Array of posts
 */
export async function getPosts(limit = 10, offset = 0) {
  const result = await query(
    `SELECT p.*, u.username, u.user_type, u.is_verified 
     FROM posts p 
     JOIN users u ON p.user_id = u.id 
     ORDER BY p.created_at DESC 
     LIMIT $1 OFFSET $2`,
    [limit, offset],
  )
  return result.rows
}

/**
 * Gets a post by ID
 * @param postId Post ID
 * @returns Post object
 */
export async function getPostById(postId: string) {
  const result = await query(
    `SELECT p.*, u.username, u.user_type, u.is_verified 
     FROM posts p 
     JOIN users u ON p.user_id = u.id 
     WHERE p.id = $1`,
    [postId],
  )
  return result.rows[0]
}

/**
 * Creates a new post
 * @param userId User ID
 * @param title Post title
 * @param contentHash IPFS content hash
 * @param category Post category
 * @returns Created post
 */
export async function createPost(userId: string, title: string, contentHash: string, category: string) {
  const result = await query(
    "INSERT INTO posts (user_id, title, content_hash, category, is_verified, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW()) RETURNING *",
    [userId, title, contentHash, category, false],
  )
  return result.rows[0]
}

/**
 * Gets comments for a post
 * @param postId Post ID
 * @returns Array of comments
 */
export async function getCommentsByPostId(postId: string) {
  const result = await query(
    `SELECT c.*, u.username, u.user_type, u.is_verified 
     FROM comments c 
     JOIN users u ON c.user_id = u.id 
     WHERE c.post_id = $1 
     ORDER BY c.created_at ASC`,
    [postId],
  )
  return result.rows
}

/**
 * Creates a new comment
 * @param postId Post ID
 * @param userId User ID
 * @param content Comment content
 * @returns Created comment
 */
export async function createComment(postId: string, userId: string, content: string) {
  const result = await query(
    "INSERT INTO comments (post_id, user_id, content, created_at) VALUES ($1, $2, $3, NOW()) RETURNING *",
    [postId, userId, content],
  )
  return result.rows[0]
}

/**
 * Gets verification requests
 * @param status Status filter (pending, approved, rejected)
 * @returns Array of verification requests
 */
export async function getVerificationRequests(status?: string) {
  let query = `
    SELECT vr.*, u.username, u.user_type 
    FROM verification_requests vr 
    JOIN users u ON vr.user_id = u.id
  `

  const params: any[] = []

  if (status) {
    query += " WHERE vr.status = $1"
    params.push(status)
  }

  query += " ORDER BY vr.created_at DESC"

  const result = await query(query, params)
  return result.rows
}

/**
 * Creates a verification request
 * @param userId User ID
 * @param documentUrls Array of document URLs
 * @returns Created verification request
 */
export async function createVerificationRequest(userId: string, documentUrls: string[]) {
  const result = await query(
    "INSERT INTO verification_requests (user_id, document_urls, status, created_at) VALUES ($1, $2, $3, NOW()) RETURNING *",
    [userId, documentUrls, "pending"],
  )
  return result.rows[0]
}

/**
 * Updates a verification request status
 * @param requestId Request ID
 * @param status New status (approved, rejected)
 * @param adminId Admin user ID
 * @returns Updated verification request
 */
export async function updateVerificationRequestStatus(requestId: string, status: string, adminId: string) {
  const result = await query(
    "UPDATE verification_requests SET status = $1, admin_id = $2, updated_at = NOW() WHERE id = $3 RETURNING *",
    [status, adminId, requestId],
  )

  // If approved, update user verification status
  if (status === "approved") {
    const request = result.rows[0]
    await query("UPDATE users SET is_verified = TRUE WHERE id = $1", [request.user_id])
  }

  return result.rows[0]
}

/**
 * Gets flagged content
 * @param status Status filter (flagged, under_vote, removed)
 * @returns Array of flagged content
 */
export async function getFlaggedContent(status?: string) {
  let queryText = `
    SELECT fc.*, p.title, p.content_hash, p.category, u.username, u.user_type, u.is_verified 
    FROM flagged_content fc 
    JOIN posts p ON fc.post_id = p.id 
    JOIN users u ON p.user_id = u.id
  `

  const params: any[] = []

  if (status) {
    queryText += " WHERE fc.status = $1"
    params.push(status)
  }

  queryText += " ORDER BY fc.created_at DESC"

  const result = await query(queryText, params)
  return result.rows
}

/**
 * Flags content
 * @param postId Post ID
 * @param userId User ID reporting the content
 * @param reason Reason for flagging
 * @returns Created flag
 */
export async function flagContent(postId: string, userId: string, reason: string) {
  // Check if content is already flagged
  const existingFlag = await query("SELECT * FROM flagged_content WHERE post_id = $1", [postId])

  if (existingFlag.rows.length > 0) {
    // Add a report to existing flag
    await query(
      "INSERT INTO content_reports (flagged_content_id, user_id, reason, created_at) VALUES ($1, $2, $3, NOW())",
      [existingFlag.rows[0].id, userId, reason],
    )

    // Update report count
    await query("UPDATE flagged_content SET report_count = report_count + 1 WHERE id = $1", [existingFlag.rows[0].id])

    return existingFlag.rows[0]
  } else {
    // Create new flagged content entry
    const result = await query(
      "INSERT INTO flagged_content (post_id, status, report_count, created_at) VALUES ($1, $2, $3, NOW()) RETURNING *",
      [postId, "flagged", 1],
    )

    const flaggedContentId = result.rows[0].id

    // Add initial report
    await query(
      "INSERT INTO content_reports (flagged_content_id, user_id, reason, created_at) VALUES ($1, $2, $3, NOW())",
      [flaggedContentId, userId, reason],
    )

    return result.rows[0]
  }
}

/**
 * Initiates a vote on flagged content
 * @param flaggedContentId Flagged content ID
 * @param adminId Admin user ID
 * @param duration Vote duration in hours
 * @returns Created vote
 */
export async function initiateContentVote(flaggedContentId: string, adminId: string, duration: number) {
  // Update flagged content status
  await query("UPDATE flagged_content SET status = $1 WHERE id = $2", ["under_vote", flaggedContentId])

  // Calculate end time
  const endTime = new Date()
  endTime.setHours(endTime.getHours() + duration)

  // Create vote
  const result = await query(
    "INSERT INTO content_votes (flagged_content_id, admin_id, end_time, created_at) VALUES ($1, $2, $3, NOW()) RETURNING *",
    [flaggedContentId, adminId, endTime],
  )

  return result.rows[0]
}

/**
 * Casts a vote on content
 * @param voteId Vote ID
 * @param userId User ID
 * @param decision Vote decision (keep, remove)
 * @param tokenAmount Amount of tokens used for voting
 * @returns Cast vote
 */
export async function castContentVote(voteId: string, userId: string, decision: string, tokenAmount: number) {
  const result = await query(
    "INSERT INTO content_vote_casts (vote_id, user_id, decision, token_amount, created_at) VALUES ($1, $2, $3, $4, NOW()) RETURNING *",
    [voteId, userId, decision, tokenAmount],
  )

  return result.rows[0]
}

