/* =========================================================
   SSIS CATALOG TROUBLESHOOTING SCRIPT
   ========================================================= */

-- Get Failed Packages info with message. Filter only today's date
SELECT TOP (20)
    e.execution_id, e.package_name, e.status, e.start_time, e.end_time,
    em.message_time, em.message_type, em.message_source_name, em.message
FROM SSISDB.catalog.executions e
LEFT JOIN SSISDB.catalog.event_messages em ON e.execution_id = em.operation_id
WHERE e.status = 4                                    -- Failed
  AND CONVERT(date, e.start_time) = CONVERT(date, GETDATE())
  AND em.message_type IN (120, 130)                    -- Today
ORDER BY e.execution_id DESC, em.message_time;


-- Search based on execution_id, e.g. you get the ID from SQL job failure info
SELECT execution_id, folder_name, project_name, package_name, status, start_time, end_time
FROM SSISDB.catalog.executions
WHERE execution_id = 809834;


-- Search failure reason based on execution_id, e.g. you get the ID from SQL job failure info
SELECT message_time, message_source_name, message
FROM SSISDB.catalog.event_messages
WHERE operation_id = 809834 AND message_type = 120
ORDER BY message_time;


-- Troubleshooting using GUI
/*
Integration Services Catalogs
    └── SSISDB (right click and show REPORTS)
        └── Reports
            └── All Executions (then filter failed only)
*/


/* =========================================================
   EXTRA QUERIES THAT HELP WHEN DIGGING DEEPER
   ========================================================= */

-- 1) Error-only messages (type 120) across ALL statuses, not just failed executions
--    Useful because a package can log errors and still "succeed" (status 7)
--    if the error is caught/handled.
SELECT TOP (50)
    e.execution_id, e.package_name, e.status, e.start_time, e.end_time,
    em.message_time, em.message_source_name, em.message
FROM SSISDB.catalog.executions e
JOIN SSISDB.catalog.event_messages em ON e.execution_id = em.operation_id
WHERE em.message_type = 120                            -- 120 = Error, 130 = Warning
  AND CONVERT(date, e.start_time) = CONVERT(date, GETDATE())
ORDER BY e.execution_id DESC, em.message_time;


-- 2) Parameter values used for a specific execution
--    Great for confirming what connection string / file path / env var
--    a failing run actually used.
SELECT execution_id, object_type, parameter_name, parameter_value, sensitive
FROM SSISDB.catalog.execution_parameter_values
WHERE execution_id = 809834
ORDER BY parameter_name;


-- 3) Package/task-level durations (execution_component_phases)
--    Helps identify WHICH task inside the package was slow or hung,
--    not just that the overall package failed.
SELECT
    ecp.execution_id,
    ecp.package_name,
    ecp.task_name,
    ecp.phase,
    ecp.start_time,
    ecp.end_time,
    DATEDIFF(SECOND, ecp.start_time, ecp.end_time) AS duration_seconds
FROM SSISDB.catalog.execution_component_phases ecp
WHERE ecp.execution_id = 809834
ORDER BY duration_seconds DESC;


-- 4) Long-running executions today (potential hangs / performance issues)
SELECT
    e.execution_id, e.package_name, e.status, e.start_time, e.end_time,
    DATEDIFF(MINUTE, e.start_time, ISNULL(e.end_time, GETDATE())) AS duration_minutes
FROM SSISDB.catalog.executions e
WHERE CONVERT(date, e.start_time) = CONVERT(date, GETDATE())
ORDER BY duration_minutes DESC;


-- 5) Currently running executions (status = 2) - check for stuck packages
SELECT execution_id, folder_name, project_name, package_name, start_time,
       DATEDIFF(MINUTE, start_time, GETDATE()) AS running_minutes
FROM SSISDB.catalog.executions
WHERE status = 2
ORDER BY start_time;


-- 6) Failure summary grouped by package for the last N days
--    Good for spotting a package that fails intermittently/repeatedly.
SELECT
    e.package_name,
    COUNT(*) AS failure_count,
    MAX(e.start_time) AS last_failure_time
FROM SSISDB.catalog.executions e
WHERE e.status = 4
  AND e.start_time >= DATEADD(DAY, -7, GETDATE())
GROUP BY e.package_name
ORDER BY failure_count DESC;


/* =========================================================
   REFERENCE: status codes
   1 = Created
   2 = Running
   3 = Canceled
   4 = Failed
   5 = Pending
   6 = Ended unexpectedly
   7 = Succeeded
   8 = Stopping
   9 = Completed

   REFERENCE: message_type codes
   120 = Error
   130 = Warning
   110 = Information
   ========================================================= */
