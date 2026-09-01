/* =========================================================
   SSRS (SQL Server Reporting Services) TROUBLESHOOTING SCRIPT
   Run against the ReportServer database (native mode)
   ========================================================= */

-- 1) Recent report executions - status, timing, and who ran them
--    Good starting point: filter to today, look for failures/timeouts.
--    NOTE: ExecutionLog3 already has a resolved ItemPath column - it does
--    NOT have an ItemID/ReportID to join back to Catalog on.
SELECT TOP (50)
    el.InstanceName,
    el.ItemPath,
    el.UserName,
    el.RequestType,
    el.Format,
    el.Status,
    el.TimeStart,
    el.TimeEnd,
    el.TimeDataRetrieval,
    el.TimeProcessing,
    el.TimeRendering,
    el.[RowCount],
    el.[ByteCount]
FROM ReportServer.dbo.ExecutionLog3 el
WHERE CONVERT(date, el.TimeStart) = CONVERT(date, GETDATE())
ORDER BY el.TimeStart DESC;


-- 2) Failed executions only, with error detail
--    Status <> 'rsSuccess' catches timeouts, data source errors,
--    rendering failures, parameter errors, etc.
SELECT TOP (50)
    el.ItemPath,
    el.UserName, el.Status, el.TimeStart, el.TimeEnd,
    el.Parameters
FROM ReportServer.dbo.ExecutionLog3 el
WHERE el.Status <> 'rsSuccess'
  AND el.TimeStart >= DATEADD(DAY, -7, GETDATE())
ORDER BY el.TimeStart DESC;


-- 3) Slow-running reports (last 7 days)
--    Breaks total time into data retrieval / processing / rendering
--    so you know WHERE the time is going (bad query vs. big render vs. subscription overhead).
SELECT TOP (50)
    el.ItemPath,
    el.TimeStart,
    el.TimeDataRetrieval, el.TimeProcessing, el.TimeRendering,
    (el.TimeDataRetrieval + el.TimeProcessing + el.TimeRendering) AS TotalTimeMs
FROM ReportServer.dbo.ExecutionLog3 el
WHERE el.TimeStart >= DATEADD(DAY, -7, GETDATE())
ORDER BY TotalTimeMs DESC;


-- 4) Search execution history for a specific report by path/name
SELECT TOP (50)
    el.InstanceName, el.UserName, el.RequestType, el.Format, el.Status,
    el.TimeStart, el.TimeEnd, el.Parameters
FROM ReportServer.dbo.ExecutionLog3 el
WHERE el.ItemPath LIKE '%YourReportNameHere%'
ORDER BY el.TimeStart DESC;


-- 5) Subscriptions - list all, with last run status/time
--    Useful for "why didn't my subscription email go out" type issues.
--    Subscriptions.OwnerID is a GUID - join to Users for the readable name.
SELECT
    s.SubscriptionID, c.Name AS ReportName, c.Path AS ReportPath,
    s.Description, s.EventType, s.LastStatus, s.LastRunTime,
    s.DeliveryExtension, u.UserName AS Owner
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON s.Report_OID = c.ItemID
LEFT JOIN ReportServer.dbo.Users u ON s.OwnerID = u.UserID
ORDER BY s.LastRunTime DESC;


-- 6) Failed / errored subscriptions only
SELECT
    s.SubscriptionID, c.Name AS ReportName, c.Path AS ReportPath,
    s.LastStatus, s.LastRunTime, s.Description, u.UserName AS Owner
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON s.Report_OID = c.ItemID
LEFT JOIN ReportServer.dbo.Users u ON s.OwnerID = u.UserID
WHERE s.LastStatus LIKE '%error%'
   OR s.LastStatus LIKE '%fail%'
ORDER BY s.LastRunTime DESC;


-- 7) Scheduled jobs behind a subscription (ReportServer schedule -> SQL Agent job link)
--    Helps when a subscription silently stops firing - check if the
--    underlying schedule/job is still active.
SELECT
    sch.ScheduleID, sch.Name AS ScheduleName, sch.NextRunTime, sch.LastRunTime,
    sch.State, sub.SubscriptionID, c.Name AS ReportName
FROM ReportServer.dbo.Schedule sch
LEFT JOIN ReportServer.dbo.ReportSchedule rs ON sch.ScheduleID = rs.ScheduleID
LEFT JOIN ReportServer.dbo.Subscriptions sub ON rs.SubscriptionID = sub.SubscriptionID
LEFT JOIN ReportServer.dbo.Catalog c ON rs.ReportID = c.ItemID
ORDER BY sch.NextRunTime;


-- 8) Report cache / snapshot status
--    Confirms whether a report is running live vs. from a cached/snapshot copy,
--    which explains "stale data" complaints. Cache data lives in the
--    SEPARATE ReportServerTempDB database, not ReportServer, and the
--    table name depends on your SSRS version - use whichever exists:
--
--    Newer SSRS versions (table: ContentCache):
SELECT
    c.Name AS ReportName, c.Path,
    cc.CreatedDate, cc.ExpirationDate
FROM ReportServer.dbo.Catalog c
JOIN ReportServerTempDB.dbo.ContentCache cc ON c.ItemID = cc.CatalogItemID
ORDER BY cc.ExpirationDate DESC;

--    Older SSRS versions (table: ExecutionCache):
-- SELECT
--     c.Name AS ReportName, c.Path,
--     ec.AbsoluteExpiration
-- FROM ReportServer.dbo.Catalog c
-- JOIN ReportServerTempDB.dbo.ExecutionCache ec ON c.ItemID = ec.ReportID
-- ORDER BY ec.AbsoluteExpiration DESC;


-- 9) Data source / connection info per report
--    Confirms which data source (and shared vs. embedded) a report is
--    pointed at - useful when troubleshooting "wrong environment" data issues.
SELECT
    c.Name AS ReportName, c.Path,
    ds.Name AS DataSourceName, ds.ConnectionString, ds.Extension
FROM ReportServer.dbo.Catalog c
JOIN ReportServer.dbo.DataSource ds ON c.ItemID = ds.ItemID
ORDER BY c.Name;


-- 10) Currently running jobs (live, right now)
--    dbo.RunningJobs is the table behind the "Manage Jobs" screen in the
--    web portal - use it to spot a report/subscription/refresh that's
--    hung. RequestPath is already a plain text column here (no Catalog
--    join needed). Only reflects jobs actively in progress, not queued
--    ones, and won't show anything served from cache.
SELECT
    rj.JobID, rj.RequestName, rj.RequestPath, rj.ComputerName,
    u.UserName, rj.StartDate, rj.Timeout, rj.JobAction, rj.JobType, rj.JobStatus,
    DATEDIFF(MINUTE, rj.StartDate, GETDATE()) AS RunningMinutes
FROM ReportServer.dbo.RunningJobs rj
LEFT JOIN ReportServer.dbo.Users u ON rj.UserId = u.UserID
ORDER BY rj.StartDate;


-- 11) Users known to the report server
--    Useful when troubleshooting "user can't access report" issues -
--    confirms whether SSRS has ever seen/cached this login.
SELECT UserID, UserName, Sid
FROM ReportServer.dbo.Users
ORDER BY UserName;


-- 12) A specific user's effective permissions (roles) per catalog item
--    Answers "why does/doesn't this user see this report" questions.
SELECT
    u.UserName,
    c.Name AS ItemName, c.Path,
    r.RoleName
FROM ReportServer.dbo.PolicyUserRole pur
JOIN ReportServer.dbo.Users u ON pur.UserID = u.UserID
JOIN ReportServer.dbo.Roles r ON pur.RoleID = r.RoleID
JOIN ReportServer.dbo.Policies p ON pur.PolicyID = p.PolicyID
JOIN ReportServer.dbo.Catalog c ON p.PolicyID = c.PolicyID
WHERE u.UserName LIKE '%YourUserNameHere%'
ORDER BY c.Path;


-- 13) Error counts grouped by report over the last 30 days
--     Spot the "problem child" reports that fail repeatedly.
SELECT
    el.ItemPath,
    COUNT(*) AS FailureCount,
    MAX(el.TimeStart) AS LastFailureTime
FROM ReportServer.dbo.ExecutionLog3 el
WHERE el.Status <> 'rsSuccess'
  AND el.TimeStart >= DATEADD(DAY, -30, GETDATE())
GROUP BY el.ItemPath
ORDER BY FailureCount DESC;


/* =========================================================
   TROUBLESHOOTING VIA GUI / TOOLS
   =========================================================
   Report Server logs (on the report server machine, not the DB):
   C:\Program Files\Microsoft SQL Server Reporting Services\
       SSRS\LogFiles\ReportServerService_<date>.log
       -> good for server-side crashes, rendering extension errors,
          service startup issues that never make it into ExecutionLog3

   Report Server web portal:
   /Reports  (or /Reports_<InstanceName>)
       -> browse folder, check item history/snapshots per report

   Reporting Services Configuration Manager:
       -> verify Service Account, Web Service URL, Database
          connection, and Encryption Keys are healthy
*/


/* =========================================================
   REFERENCE: common ExecutionLog3.Status values
   rsSuccess
   rsTimeout
   rsAuthorizationDenied
   rsAuthenticationFailure
   rsParameterError
   rsSubscriptionError
   rsUnknownError
   rsExceededRateLimit
   rsRuntimeError

   REFERENCE: Catalog.Type values
   1 = Folder
   2 = Report
   3 = Resource
   4 = Linked Report
   5 = Data Source
   6 = Model
   7 = Report Part
   8 = Shared Dataset
   ========================================================= */
