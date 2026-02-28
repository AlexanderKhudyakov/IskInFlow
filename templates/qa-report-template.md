# QA Verification Report: Task [Task Number]

**Task**: [Task Name]
**Task File**: [Path to task file]
**PR/Branch**: [PR URL or branch name]
**QA Engineer**: AI QA Engineer
**Test Date**: [Date and Time]
**Status**: [PASS ✅ / FAIL ❌ / CONDITIONAL_PASS ⚠️]

---

## Executive Summary

[2-3 paragraph summary of testing performed and overall assessment]

**Overall Result**: [PASS/FAIL/CONDITIONAL_PASS]
**Recommendation**: [Approve / Request Changes / Needs Discussion]

**Quick Stats**:
- Objectives Met: [X/Y]
- Acceptance Criteria Met: [X/Y]
- Tests Passed: [X/Y]
- Test Coverage: [X%]
- Critical Issues: [Number]
- Important Issues: [Number]

---

## Task Completion Verification

### Objectives Status

#### Objective 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**Verification Method**: [How verified]

**Test Performed**:
[Description of test]

**Result**:
[What you observed]

**Evidence**:
```
[Test output, logs, or description]
```

**Notes**: [Any additional observations]

---

#### Objective 2: [Description]
[Same structure as above]

---

**Overall Objectives**: [X/Y objectives met]

### Acceptance Criteria Status

#### Criterion 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**Test Performed**:
[Description]

**Expected Behavior**:
[What should happen]

**Actual Behavior**:
[What actually happened]

**Evidence**:
```
[Test results or logs]
```

---

#### Criterion 2: [Description]
[Same structure as above]

---

**Overall Acceptance Criteria**: [X/Y criteria satisfied]

---

## Automated Test Results

### Unit Tests
**Status**: PASS ✅ / FAIL ❌

**Summary**:
- Total Tests: [Number]
- Passed: [Number]
- Failed: [Number]
- Skipped: [Number]
- Execution Time: [Time]

**Output**:
```
[Paste relevant test output]
```

**Failed Tests** (if any):
1. [Test name]: [Reason for failure]
2. [Test name]: [Reason for failure]

### Integration Tests
**Status**: PASS ✅ / FAIL ❌

**Summary**:
- Total Tests: [Number]
- Passed: [Number]
- Failed: [Number]
- Execution Time: [Time]

**Output**:
```
[Paste relevant test output]
```

### End-to-End Tests
**Status**: PASS ✅ / FAIL ❌ / N/A

**Summary**:
- Total Tests: [Number]
- Passed: [Number]
- Failed: [Number]
- Execution Time: [Time]

### Test Coverage
**Overall Coverage**: [X%]
**Meets Requirement (≥80%)**: YES ✅ / NO ❌

**Breakdown**:
- Line Coverage: [X%]
- Branch Coverage: [X%]
- Function Coverage: [X%]
- Statement Coverage: [X%]

**Uncovered Critical Areas**: [List if any]

**Assessment**: [Coverage is adequate / insufficient / excellent]

---

## Manual Testing Results

### Happy Path Testing

#### Test Case 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**Steps Executed**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Result**: [Description]

**Actual Result**: [Description]

**Evidence**: [Screenshots, logs, or description]

**Notes**: [Any observations]

---

### Edge Cases Testing

#### Edge Case 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**Scenario**: [What edge case was tested]

**Input/Condition**: [The edge case]

**Expected Behavior**: [What should happen]

**Actual Behavior**: [What actually happened]

**Evidence**:
```
[Test output or logs]
```

---

#### Edge Case 2: [Description]
[Same structure]

---

**Edge Cases Summary**: [X/Y edge cases handled correctly]

### Error Handling Testing

#### Error Scenario 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**How Triggered**: [Steps to cause error]

**Expected Error Handling**:
- Error message: [Expected]
- Error code/status: [Expected]
- System state: [Expected]

**Actual Error Handling**:
- Error message: [Actual]
- Error code/status: [Actual]
- System state: [Actual]

**User-Friendliness**: [Good / Needs improvement]

**Evidence**:
```
[Error output or screenshot]
```

---

#### Error Scenario 2: [Description]
[Same structure]

---

**Error Handling Summary**: [X/Y scenarios handled correctly]

### Integration Testing

#### Integration Point 1: [Component/Service Name]
**Status**: PASS ✅ / FAIL ❌

**What Was Tested**: [Description]

**Test Steps**:
1. [Step 1]
2. [Step 2]

**Expected Behavior**: [Description]

**Actual Behavior**: [Description]

**Data Flow Verified**: YES ✅ / NO ❌

**Evidence**: [Logs or description]

---

### Exploratory Testing Findings

**Duration**: [Time spent on exploratory testing]

**Areas Explored**:
- [Area 1]
- [Area 2]
- [Area 3]

**Scenarios Tested**:
1. **[Scenario]**: [Result]
2. **[Scenario]**: [Result]
3. **[Scenario]**: [Result]

**Observations**:
- [Observation 1]
- [Observation 2]

**Issues Discovered**: [Number]
**Unexpected Behaviors**: [List if any]

---

## User Workflow Testing (if applicable)

### Workflow 1: [Description]
**Status**: PASS ✅ / FAIL ❌

**Complete Workflow**:
1. [User action 1] → [Result]
2. [User action 2] → [Result]
3. [User action 3] → [Result]
4. [User action 4] → [Result]

**Final Outcome**: [Description]

**Workflow Completion**: Successful ✅ / Failed ❌

**User Experience**: [Smooth / Has friction / Error occurred]

**Notes**: [Any observations about the workflow]

---

## Documentation Verification

### Documentation Checklist
- [ ] README updated (if required)
- [ ] API documentation present (if applicable)
- [ ] Setup instructions included
- [ ] Usage examples provided
- [ ] Error documentation present

### Documentation Accuracy
**Status**: ACCURATE ✅ / INACCURATE ❌ / INCOMPLETE ⚠️

**Issues Found**:
- [Issue 1 if any]
- [Issue 2 if any]

**Verification**:
- [ ] Examples work as documented
- [ ] Instructions are correct
- [ ] API docs match actual behavior

---

## Issues Found

### Critical Issues 🔴

**MUST be fixed before approval**

#### Issue 1: [Title]
**Severity**: Critical
**Category**: [Functionality / Testing / Documentation]
**Found During**: [Which test phase]

**Description**:
[Clear description of the issue]

**Impact**:
[Why this is critical - what breaks or fails]

**Steps to Reproduce**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Behavior**:
[What should happen according to task file]

**Actual Behavior**:
[What actually happens]

**Evidence**:
```
[Error messages, logs, screenshots]
```

**Recommendation**:
[How to fix or what needs to be done]

---

### Important Issues 🟡

**SHOULD be fixed before approval**

#### Issue 1: [Title]
**Severity**: Important
**Category**: [Testing / Documentation / Behavior]

**Description**:
[Clear description]

**Impact**:
[Why this matters]

**Evidence**:
[Supporting evidence]

**Recommendation**:
[Suggested fix]

---

### Minor Issues 🔵

**Nice to fix but not blocking**

#### Issue 1: [Title]
**Severity**: Minor
**Category**: [Enhancement / Documentation]

**Description**:
[Description]

**Recommendation**:
[Suggestion]

---

## Performance Testing Results (if applicable)

**Performance Requirements**: [From task file]

### Test Results
- Response Time: [X ms]
- Throughput: [X req/sec]
- Resource Usage: [Description]

**Meets Requirements**: YES ✅ / NO ❌

**Performance Issues**: [List if any]

---

## Positive Findings ✅

[Highlight what works exceptionally well]

- Comprehensive test coverage ([X%])
- All edge cases handled correctly
- Excellent error messages
- Smooth user workflows
- Good integration with [component]
- Clear and accurate documentation
- [Other positive findings]

---

## Completeness Assessment

### Implementation Completeness: [X%]

**Complete**:
- ✅ [Item 1]
- ✅ [Item 2]

**Incomplete**:
- ❌ [Item 1] - [What's missing]
- ❌ [Item 2] - [What's missing]

**Missing Features**: [Number]
**Incomplete Features**: [Number]

---

## Test Evidence

### Test Artifacts
- Test execution logs: [Location or attached]
- Coverage reports: [Location or attached]
- Screenshots: [Location or attached]
- Error logs: [Location or attached]

### Commands Used
```bash
# All commands executed during testing
npm test
npm run test:coverage
npm run test:integration
[Other commands]
```

### Test Environment
- Branch: [branch name]
- Commit: [commit hash]
- Environment: [dev/test/staging]
- Date/Time: [when tested]

---

## Overall Assessment

### Summary
**Total Issues Found**: [Number]
- Critical: [Number] 🔴
- Important: [Number] 🟡
- Minor: [Number] 🔵

### Quality Metrics
- Objectives Met: [X/Y] ([X%])
- Acceptance Criteria Met: [X/Y] ([X%])
- Tests Passing: [X/Y] ([X%])
- Test Coverage: [X%]
- Edge Cases Handled: [X/Y]
- Error Scenarios Handled: [X/Y]

### Strengths
1. [Strength 1]
2. [Strength 2]
3. [Strength 3]

### Weaknesses
1. [Weakness 1]
2. [Weakness 2]

### Areas of Concern
[Any areas that need attention or discussion]

---

## Decision

**QA Verification Status**: [PASS ✅ / FAIL ❌ / CONDITIONAL_PASS ⚠️]

### If PASS ✅

**The implementation is complete and correct. Approved for merge.**

**Verified**:
- ✅ All [Y] objectives are met
- ✅ All [Y] acceptance criteria are satisfied
- ✅ All tests passing ([X] tests)
- ✅ Test coverage meets requirements ([X%])
- ✅ All edge cases handled correctly
- ✅ Error handling is appropriate
- ✅ Integration works correctly
- ✅ Documentation is complete and accurate
- ✅ No critical or important issues found

**Confidence Level**: High

**Recommendation**: **APPROVE FOR MERGE**

---

### If FAIL ❌

**The implementation has critical issues. NOT approved for merge.**

**Blocking Issues**:
1. [Critical issue 1]
2. [Critical issue 2]
3. [Critical issue 3]

**Unmet Requirements**:
- ❌ Objective [X] not met: [Reason]
- ❌ Acceptance criterion [Y] not satisfied: [Reason]
- ❌ Test failures: [X] tests failing
- ❌ Missing functionality: [Description]

**Required Actions**:
1. [Action 1 - Fix critical issue]
2. [Action 2 - Complete missing feature]
3. [Action 3 - Fix failing tests]
4. Re-run all tests
5. Request QA verification again

**Recommendation**: **REQUEST CHANGES**

---

### If CONDITIONAL_PASS ⚠️

**The implementation meets core requirements but has issues.**

**Core Requirements Met**:
- ✅ [Requirement 1]
- ✅ [Requirement 2]

**Issues to Address**:
- ⚠️ [Important issue 1]
- ⚠️ [Important issue 2]

**Conditions for Approval**:
- [Condition 1]
- [Condition 2]

**Recommendation**: [Approve with conditions / Request fixes first]

---

## Next Steps

### For Developer
1. [Action item 1]
2. [Action item 2]
3. [Action item 3]

### For QA (if re-verification needed)
- [ ] Re-test after fixes
- [ ] Verify specific issues resolved
- [ ] Run regression tests
- [ ] Update QA report

---

**QA Verification Completed**: [Date and Time]
**Verified By**: AI QA Engineer
**Next Review**: [If needed, when]
