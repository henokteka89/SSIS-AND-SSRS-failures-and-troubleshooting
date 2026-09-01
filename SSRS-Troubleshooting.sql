/* =========================================================
   SSRS (SQL Server Reporting Services) TROUBLESHOOTING SCRIPT
   Run against the ReportServer database (native mode)
   ========================================================= */

-- 1) Recent report executions - status, timing, and who ran them
--    Good starting point: filter to today, look for failures/timeouts.
SELECT TOP (50)
    el.InstanceName,
    c.Name              AS ReportName,
    c.Path               AS ReportPath,
    el.UserName,
    el.RequestType,
    el.Format,
    el.Status,
    el.TimeStart,
    el.TimeEnd,
    el.TimeDataRetrieval,
    el.TimeProcessing,
    el.TimeRendering,
    el.RowCount,
    el.ByteCount
FROM ReportServer.dbo.ExecutionLog3 el
JOIN ReportServer.dbo.Catalog c ON el.ReportID = c.ItemID
WHERE CONVERT(date, el.TimeStart) = CONVERT(date, GETDATE())
ORDER BY el.TimeStart DESC;


-- 2) Failed executions only, with error detail
--    Status <> 'rsSuccess' catches timeouts, data source errors,
--    rendering failures, parameter errors, etc.
SELECT TOP (50)
    c.Name AS ReportName, c.Path AS ReportPath,
    el.UserName, el.Status, el.TimeStart, el.TimeEnd,
    el.Parameters
FROM ReportServer.dbo.ExecutionLog3 el
JOIN ReportServer.dbo.Catalog c ON el.ReportID = c.ItemID
WHERE el.Status <> 'rsSuccess'
  AND el.TimeStart >= DATEADD(DAY, -7, GETDATE())
ORDER BY el.TimeStart DESC;


-- 3) Slow-running reports (last 7 days)
--    Breaks total time into data retrieval / processing / rendering
--    so you know WHERE the time is going (bad query vs. big render vs. subscription overhead).
SELECT TOP (50)
    c.Name AS ReportName, c.Path AS ReportPath,
    el.TimeStart,
    el.TimeDataRetrieval, el.TimeProcessing, el.TimeRendering,
    (el.TimeDataRetrieval + el.TimeProcessing + el.TimeRendering) AS TotalTimeMs
FROM ReportServer.dbo.ExecutionLog3 el
JOIN ReportServer.dbo.Catalog c ON el.ReportID = c.ItemID
WHERE el.TimeStart >= DATEADD(DAY, -7, GETDATE())
ORDER BY TotalTimeMs DESC;


-- 4) Search execution history for a specific report by name
SELECT TOP (50)
    el.InstanceName, el.UserName, el.RequestType, el.Format, el.Status,
    el.TimeStart, el.TimeEnd, el.Parameters
FROM ReportServer.dbo.ExecutionLog3 el
JOIN ReportServer.dbo.Catalog c ON el.ReportID = c.ItemID
WHERE c.Name = 'YourReportNameHere'
ORDER BY el.TimeStart DESC;


-- 5) Subscriptions - list all, with last run status/time
--    Useful for "why didn't my subscription email go out" type issues.
SELECT
    s.SubscriptionID, c.Name AS ReportName, c.Path AS ReportPath,
    s.Description, s.EventType, s.LastStatus, s.LastRunTime,
    s.DeliveryExtension, s.Owner
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON s.Report_OID = c.ItemID
ORDER BY s.LastRunTime DESC;


-- 6) Failed / errored subscriptions only
SELECT
    s.SubscriptionID, c.Name AS ReportName, c.Path AS ReportPath,
    s.LastStatus, s.LastRunTime, s.Description, s.Owner
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON s.Report_OID = c.ItemID
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
--    which explains "stale data" complaints.
SELECT
    c.Name AS ReportName, c.Path,
    ce.ExpirationDate, ce.Timestamp AS CachedTimestamp
FROM ReportServer.dbo.Catalog c
LEFT JOIN ReportServer.dbo.Cache ce ON c.ItemID = ce.ItemID
WHERE c.Type = 2   -- 2 = Report
ORDER BY ce.Timestamp DESC;


-- 9) Data source / connection info per report
--    Confirms which data source (and shared vs. embedded) a report is
--    pointed at - useful when troubleshooting "wrong environment" data issues.
SELECT
    c.Name AS ReportName, c.Path,
    ds.Name AS DataSourceName, ds.ConnectionString, ds.Extension
FROM ReportServer.dbo.Catalog c
JOIN ReportServer.dbo.DataSource ds ON c.ItemID = ds.ItemID
ORDER BY c.Name;


-- 10) Error counts grouped by report over the last 30 days
--     Spot the "problem child" reports that fail repeatedly.
SELECT
    c.Name AS ReportName, c.Path,
    COUNT(*) AS FailureCount,
    MAX(el.TimeStart) AS LastFailureTime
FROM ReportServer.dbo.ExecutionLog3 el
JOIN ReportServer.dbo.Catalog c ON el.ReportID = c.ItemID
WHERE el.Status <> 'rsSuccess'
  AND el.TimeStart >= DATEADD(DAY, -30, GETDATE())
GROUP BY c.Name, c.Path
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
