 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DeNewsContent
 * @dev Contract for managing news content on the DeNews platform with censorship resistance
 */
contract DeNewsContent is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    
    // Counter for post IDs
    Counters.Counter private _postIdCounter;
    // Counter for comment IDs
    Counters.Counter private _commentIdCounter;
    // Counter for governance proposal IDs
    Counters.Counter private _proposalIdCounter;
    
    // User types for verification
    enum UserType { Individual, Journalist, Organization }
    
    // Content moderation status
    enum ModerationStatus { None, Flagged, UnderVote, Removed }
    
    // Governance proposal status
    enum ProposalStatus { Active, Passed, Rejected, Executed }
    
    // Governance proposal type
    enum ProposalType { RemoveContent, UpdateParameters, GrantRole, RevokeRole }
    
    // Struct to represent a user profile
    struct UserProfile {
        address userAddress;
        string username;
        string metadataHash; // IPFS hash of additional user metadata
        UserType userType;
        bool isVerified;
        uint256 registrationTime;
    }
    
    // Struct to represent a news post
    struct NewsPost {
        uint256 id;
        address author;
        string contentHash; // IPFS hash of the content
        string metadataHash; // IPFS hash of additional metadata
        uint256 timestamp;
        string category;
        uint256 likes;
        uint256 comments;
        ModerationStatus moderationStatus;
    }
    
    // Struct to represent a comment
    struct Comment {
        uint256 id;
        uint256 postId;
        address author;
        string content;
        uint256 timestamp;
        ModerationStatus moderationStatus;
    }
    
    // Struct to represent a governance proposal
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        bytes data; // Encoded data specific to the proposal type
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        ProposalStatus status;
        string descriptionHash; // IPFS hash of proposal description
    }
    
    // Struct to represent content moderation vote
    struct ModerationVote {
        uint256 proposalId;
        uint256 postId;
        uint256 startTime;
        uint256 endTime;
        uint256 forRemovalVotes;
        uint256 againstRemovalVotes;
        bool executed;
    }
    
    // Mapping from user address to UserProfile
    mapping(address => UserProfile) public users;
    
    // Mapping from post ID to NewsPost
    mapping(uint256 => NewsPost) public posts;
    
    // Mapping from post ID to array of comments
    mapping(uint256 => Comment[]) public postComments;
    
    // Mapping from user address to array of post IDs
    mapping(address => uint256[]) public userPosts;
    
    // Mapping from user address to array of addresses they follow
    mapping(address => address[]) public following;
    
    // Mapping from post ID to mapping of user address to whether they liked the post
    mapping(uint256 => mapping(address => bool)) public postLikes;
    
    // Mapping from proposal ID to Proposal
    mapping(uint256 => Proposal) public proposals;
    
    // Mapping from proposal ID to mapping of user address to whether they voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    // Mapping from post ID to ModerationVote
    mapping(uint256 => ModerationVote) public moderationVotes;
    
    // Platform parameters
    uint256 public flagThreshold = 3; // Number of flags needed to mark content as flagged
    uint256 public voteDuration = 3 days; // Duration of governance votes
    uint256 public quorumPercentage = 10; // Percentage of token holders required for quorum
    
    // Events
    event UserRegistered(address indexed userAddress, string username, UserType userType);
    event UserVerified(address indexed userAddress);
    event PostCreated(uint256 indexed postId, address indexed author, string contentHash);
    event PostLiked(uint256 indexed postId, address indexed liker);
    event PostUnliked(uint256 indexed postId, address indexed unliker);
    event CommentAdded(uint256 indexed postId, uint256 indexed commentId, address indexed commenter);
    event ContentFlagged(uint256 indexed postId, address indexed flagger);
    event ModerationVoteStarted(uint256 indexed postId, uint256 indexed proposalId);
    event ModerationVoteEnded(uint256 indexed postId, bool removed);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, ProposalType proposalType);
    event ProposalVoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event UserFollowed(address indexed follower, address indexed followed);
    
    /**
     * @dev Constructor that sets up the initial admin role
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Registers a new user
     * @param username Username of the user
     * @param metadataHash IPFS hash of additional user metadata
     * @param userType Type of the user (Individual, Journalist, Organization)
     */
    function registerUser(string memory username, string memory metadataHash, UserType userType) external {
        require(users[msg.sender].registrationTime == 0, "User already registered");
        
        users[msg.sender] = UserProfile({
            userAddress: msg.sender,
            username: username,
            metadataHash: metadataHash,
            userType: userType,
            isVerified: false,
            registrationTime: block.timestamp
        });
        
        emit UserRegistered(msg.sender, username, userType);
    }
    
    /**
     * @dev Verifies a user (only callable by admin or moderator)
     * @param userAddress Address of the user to verify
     */
    function verifyUser(address userAddress) external onlyRole(MODERATOR_ROLE) {
        require(users[userAddress].registrationTime > 0, "User not registered");
        require(!users[userAddress].isVerified, "User already verified");
        
        users[userAddress].isVerified = true;
        
        emit UserVerified(userAddress);
    }
    
    /**
     * @dev Creates a new news post with censorship resistance
     * @param contentHash IPFS hash of the content
     * @param metadataHash IPFS hash of additional metadata
     * @param category Category of the news post
     * @return postId ID of the created post
     */
    function createPost(string memory contentHash, string memory metadataHash, string memory category) external returns (uint256) {
        require(users[msg.sender].registrationTime > 0, "User not registered");
        
        uint256 postId = _postIdCounter.current();
        _postIdCounter.increment();
        
        posts[postId] = NewsPost({
            id: postId,
            author: msg.sender,
            contentHash: contentHash,
            metadataHash: metadataHash,
            timestamp: block.timestamp,
            category: category,
            likes: 0,
            comments: 0,
            moderationStatus: ModerationStatus.None
        });
        
        userPosts[msg.sender].push(postId);
        
        emit PostCreated(postId, msg.sender, contentHash);
        
        return postId;
    }
    
    /**
     * @dev Likes a post
     * @param postId ID of the post to like
     */
    function likePost(uint256 postId) external {
        require(posts[postId].author != address(0), "Post does not exist");
        require(!postLikes[postId][msg.sender], "Already liked this post");
        
        postLikes[postId][msg.sender] = true;
        posts[postId].likes += 1;
        
        emit PostLiked(postId, msg.sender);
    }
    
    /**
     * @dev Unlikes a post
     * @param postId ID of the post to unlike
     */
    function unlikePost(uint256 postId) external {
        require(posts[postId].author != address(0), "Post does not exist");
        require(postLikes[postId][msg.sender], "Haven't liked this post");
        
        postLikes[postId][msg.sender] = false;
        posts[postId].likes -= 1;
        
        emit PostUnliked(postId, msg.sender);
    }
    
    /**
     * @dev Adds a comment to a post
     * @param postId ID of the post to comment on
     * @param content Content of the comment
     * @return commentId ID of the created comment
     */
    function addComment(uint256 postId, string memory content) external returns (uint256) {
        require(posts[postId].author != address(0), "Post does not exist");
        require(users[msg.sender].registrationTime > 0, "User not registered");
        
        uint256 commentId = _commentIdCounter.current();
        _commentIdCounter.increment();
        
        Comment memory newComment = Comment({
            id: commentId,
            postId: postId,
            author: msg.sender,
            content: content,
            timestamp: block.timestamp,
            moderationStatus: ModerationStatus.None
        });
        
        postComments[postId].push(newComment);
        posts[postId].comments += 1;
        
        emit CommentAdded(postId, commentId, msg.sender);
        
        return commentId;
    }
    
    /**
     * @dev Flags content for moderation
     * @param postId ID of the post to flag
     */
    function flagContent(uint256 postId) external {
        require(posts[postId].author != address(0), "Post does not exist");
        require(users[msg.sender].registrationTime > 0, "User not registered");
        require(posts[postId].moderationStatus == ModerationStatus.None, "Content already flagged or under review");
        
        // In a real implementation, we would track individual flags and count them
        // For simplicity, we're just setting the status directly
        posts[postId].moderationStatus = ModerationStatus.Flagged;
        
        emit ContentFlagged(postId, msg.sender);
        
        // If we had a flag threshold, we would check it here and potentially start a vote
    }
    
    /**
     * @dev Starts a moderation vote for flagged content
     * @param postId ID of the post to vote on
     */
    function startModerationVote(uint256 postId) external onlyRole(MODERATOR_ROLE) {
        require(posts[postId].author != address(0), "Post does not exist");
        require(posts[postId].moderationStatus == ModerationStatus.Flagged, "Content not flagged");
        
        uint256 proposalId = _proposalIdCounter.current();
        _proposalIdCounter.increment();
        
        // Create proposal data
        bytes memory proposalData = abi.encode(postId);
        
        // Create governance proposal
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            proposalType: ProposalType.RemoveContent,
            data: proposalData,
            startTime: block.timestamp,
            endTime: block.timestamp + voteDuration,
            forVotes: 0,
            againstVotes: 0,
            status: ProposalStatus.Active,
            descriptionHash: ""
        });
        
        // Create moderation vote
        moderationVotes[postId] = ModerationVote({
            proposalId: proposalId,
            postId: postId,
            startTime: block.timestamp,
            endTime: block.timestamp + voteDuration,
            forRemovalVotes: 0,
            againstRemovalVotes: 0,
            executed: false
        });
        
        // Update post status
        posts[postId].moderationStatus = ModerationStatus.UnderVote;
        
        emit ModerationVoteStarted(postId, proposalId);
        emit ProposalCreated(proposalId, msg.sender, ProposalType.RemoveContent);
    }
    
    /**
     * @dev Casts a vote on a moderation proposal
     * @param proposalId ID of the proposal
     * @param support Whether to support the proposal (true = remove, false = keep)
     * @param voteWeight Weight of the vote (based on token balance or reputation)
     */
    function castModerationVote(uint256 proposalId, bool support, uint256 voteWeight) external nonReentrant {
        require(proposals[proposalId].id == proposalId, "Proposal does not exist");
        require(proposals[proposalId].status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp < proposals[proposalId].endTime, "Voting period ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(users[msg.sender].registrationTime > 0, "User not registered");
        
        // Record that user has voted
        hasVoted[proposalId][msg.sender] = true;
        
        // Update vote counts
        if (support) {
            proposals[proposalId].forVotes += voteWeight;
            
            // If this is a content moderation proposal, update the moderation vote too
            if (proposals[proposalId].proposalType == ProposalType.RemoveContent) {
                uint256 postId = abi.decode(proposals[proposalId].data, (uint256));
                moderationVotes[postId].forRemovalVotes += voteWeight;
            }
        } else {
            proposals[proposalId].againstVotes += voteWeight;
            
            // If this is a content moderation proposal, update the moderation vote too
            if (proposals[proposalId].proposalType == ProposalType.RemoveContent) {
                uint256 postId = abi.decode(proposals[proposalId].data, (uint256));
                moderationVotes[postId].againstRemovalVotes += voteWeight;
            }
        }
        
        emit ProposalVoteCast(proposalId, msg.sender, support);
    }
    
    /**
     * @dev Executes a moderation vote after voting period ends
     * @param postId ID of the post that was voted on
     */
    function executeModerationVote(uint256 postId) external {
        ModerationVote storage vote = moderationVotes[postId];
        require(vote.postId == postId, "Vote does not exist");
        require(!vote.executed, "Vote already executed");
        require(block.timestamp >= vote.endTime, "Voting period not ended");
        
        vote.executed = true;
        
        // Get the associated proposal
        Proposal storage proposal = proposals[vote.proposalId];
        
        // Check if quorum was reached (simplified)
        bool quorumReached = (proposal.forVotes + proposal.againstVotes) > 0; // In reality, check against total token supply
        
        // Determine outcome
        bool contentRemoved = false;
        
        if (quorumReached && proposal.forVotes > proposal.againstVotes) {
            // Vote passed, content should be removed
            posts[postId].moderationStatus = ModerationStatus.Removed;
            proposal.status = ProposalStatus.Executed;
            contentRemoved = true;
        } else {
            // Vote failed or no quorum, content stays
            posts[postId].moderationStatus = ModerationStatus.None;
            proposal.status = ProposalStatus.Rejected;
        }
        
        emit ModerationVoteEnded(postId, contentRemoved);
        emit ProposalExecuted(vote.proposalId);
    }
    
    /**
     * @dev Creates a governance proposal
     * @param proposalType Type of proposal
     * @param data Encoded data specific to the proposal type
     * @param descriptionHash IPFS hash of proposal description
     * @return proposalId ID of the created proposal
     */
    function createProposal(ProposalType proposalType, bytes memory data, string memory descriptionHash) external returns (uint256) {
        require(users[msg.sender].registrationTime > 0, "User not registered");
        
        uint256 proposalId = _proposalIdCounter.current();
        _proposalIdCounter.increment();
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            proposalType: proposalType,
            data: data,
            startTime: block.timestamp,
            endTime: block.timestamp + voteDuration,
            forVotes: 0,
            againstVotes: 0,
            status: ProposalStatus.Active,
            descriptionHash: descriptionHash
        });
        
        emit ProposalCreated(proposalId, msg.sender, proposalType);
        
        return proposalId;
    }
    
    /**
     * @dev Executes a governance proposal after voting period ends
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id == proposalId, "Proposal does not exist");
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        
        // Check if quorum was reached (simplified)
        bool quorumReached = (proposal.forVotes + proposal.againstVotes) > 0; // In reality, check against total token supply
        
        if (quorumReached && proposal.forVotes > proposal.againstVotes) {
            // Vote passed, execute the proposal
            if (proposal.proposalType == ProposalType.UpdateParameters) {
                // Decode parameter update data
                (string memory paramName, uint256 newValue) = abi.decode(proposal.data, (string, uint256));
                
                // Update the appropriate parameter
                if (keccak256(bytes(paramName)) == keccak256(bytes("flagThreshold"))) {
                    flagThreshold = newValue;
                } else if (keccak256(bytes(paramName)) == keccak256(bytes("voteDuration"))) {
                    voteDuration = newValue;
                } else if (keccak256(bytes(paramName)) == keccak256(bytes("quorumPercentage"))) {
                    quorumPercentage = newValue;
                }
            } else if (proposal.proposalType == ProposalType.GrantRole) {
                // Decode role grant data
                (bytes32 role, address account) = abi.decode(proposal.data, (bytes32, address));
                
                // Grant the role
                _grantRole(role, account);
            } else if (proposal.proposalType == ProposalType.RevokeRole) {
                // Decode role revocation data
                (bytes32 role, address account) = abi.decode(proposal.data, (bytes32, address));
                
                // Revoke the role
                _revokeRole(role, account);
            }
            
            proposal.status = ProposalStatus.Executed;
        } else {
            // Vote failed or no quorum
            proposal.status = ProposalStatus.Rejected;
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    /**
     * @dev Follows a user
     * @param userToFollow Address of the user to follow
     */
    function followUser(address userToFollow) external {
        require(userToFollow != msg.sender, "Cannot follow yourself");
        require(users[userToFollow].registrationTime > 0, "User to follow does not exist");
        require(users[msg.sender].registrationTime > 0, "User not registered");
        
        // Check if already following
        address[] storage followingList = following[msg.sender];
        for (uint i = 0; i < followingList.length; i++) {
            if (followingList[i] == userToFollow) {
                revert("Already following this user");
            }
        }
        
        following[msg.sender].push(userToFollow);
        emit UserFollowed(msg.sender, userToFollow);
    }
    
    /**
     * @dev Gets all posts by a user
     * @param user Address of the user
     * @return Array of post IDs
     */
    function getPostsByUser(address user) external view returns (uint256[] memory) {
        return userPosts[user];
    }
    
    /**
     * @dev Gets all users followed by a user
     * @param user Address of the user
     * @return Array of followed addresses
     */
    function getFollowing(address user) external view returns (address[] memory) {
        return following[user];
    }
    
    /**
     * @dev Gets all comments for a post
     * @param postId ID of the post
     * @return Array of comments
     */
    function getCommentsByPost(uint256 postId) external view returns (Comment[] memory) {
        return postComments[postId];
    }
    
    /**
     * @dev Checks if a user has liked a post
     * @param postId ID of the post
     * @param user Address of the user
     * @return Whether the user has liked the post
     */
    function hasLiked(uint256 postId, address user) external view returns (bool) {
        return postLikes[postId][user];
    }
    
    /**
     * @dev Gets user type and verification status
     * @param user Address of the user
     * @return userType Type of the user
     * @return isVerified Whether the user is verified
     */
    function getUserVerificationInfo(address user) external view returns (UserType, bool) {
        return (users[user].userType, users[user].isVerified);
    }
}

