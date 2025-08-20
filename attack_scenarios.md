# Attack Scenarios for Obtaining Token IDs

## Scenario 1: Information Disclosure Vulnerabilities

### 1.1 API Response Leakage
- **Vulnerability**: API endpoints that return token IDs in error messages
- **Example**: 
  ```
  GET /api/v4/projects/123/access_tokens
  Response: {"error": "Token ID 456 is invalid"}
  ```

### 1.2 Log Files
- **Vulnerability**: Token IDs logged in application logs
- **Example**: 
  ```
  [ERROR] Invalid token ID: 789 for user: admin
  ```

### 1.3 Error Messages
- **Vulnerability**: Detailed error messages exposing token IDs
- **Example**:
  ```
  "Personal Access Token with ID 123 has been revoked"
  ```

## Scenario 2: Database Access

### 2.1 SQL Injection
- **Vulnerability**: SQL injection in token-related queries
- **Example**:
  ```sql
  SELECT id FROM personal_access_tokens WHERE user_id = 1
  ```

### 2.2 Database Dumps
- **Vulnerability**: Compromised database backups
- **Example**: Attacker gains access to database dump containing token IDs

## Scenario 3: Internal Access

### 3.1 Compromised Admin Account
- **Vulnerability**: Attacker gains admin access
- **Method**: Use admin API to list all tokens
  ```
  GET /api/v4/users/{user_id}/personal_access_tokens
  ```

### 3.2 Insider Threat
- **Vulnerability**: Malicious employee with database access
- **Method**: Direct database queries to extract token IDs

## Scenario 4: Predictable Token IDs

### 4.1 Sequential IDs
- **Vulnerability**: Token IDs are sequential and predictable
- **Example**: If you know one token ID is 100, others might be 101, 102, etc.

### 4.2 Enumeration Attacks
- **Vulnerability**: Brute force token ID enumeration
- **Method**: Try different token IDs in JWT payloads

## Scenario 5: JWT Token Analysis

### 5.1 Decoded JWT Tokens
- **Vulnerability**: Existing JWT tokens contain token IDs
- **Method**: Decode existing JWT tokens to extract embedded token IDs

### 5.2 Token Reuse
- **Vulnerability**: Same token ID used in multiple JWT tokens
- **Method**: Extract token ID from one JWT and reuse in another