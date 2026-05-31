-- ============================================================================
-- PERFORMANCE & OPTIMIZATION INDEXES
-- ============================================================================
CREATE INDEX `idx_emp_credential` ON `employees` (`username`, `password`, `role`);
CREATE INDEX `idx_perf_transaction_lookup` ON `performance_records` (`appraisal_period_id`, `employee_id`, `project_id`);
CREATE INDEX `idx_contrib_scores_lookup` ON `contributions` (`appraisal_period_id`, `employee_id`, `contribution_score`);
CREATE INDEX `idx_assignment_lookup` ON `project_assignments` (`project_id`, `employee_id`);

-- ============================================================================
-- PERFORMANCE records INSERT & UPDATE TRIGGERS
-- ============================================================================
DELIMITER //

-- 1. Consolidated INSERT Pipeline: locked vs active Verification + calculate scoring
CREATE TRIGGER `before_performance_insert_pipeline`
BEFORE INSERT ON `performance_records`
FOR EACH ROW
BEGIN
    DECLARE `v_period_status` VARCHAR(10);
    DECLARE `v_user_role` VARCHAR(20);
    DECLARE `v_complexity` INT;
    DECLARE `v_difficulty` VARCHAR(10);
    DECLARE `v_difficulty_multiplier` INT DEFAULT 1;
    DECLARE `v_calculated_score` DECIMAL(5,2) DEFAULT 0.00;
    
    -- PHASE 1: Security Validation Gate Check
    SELECT `status` INTO `v_period_status` 
    FROM `appraisal_periods` 
    WHERE `id` = NEW.`appraisal_period_id`;
    
    IF `v_period_status` = 'Locked' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Security Violation: Cannot insert new performance records into a Locked appraisal period.';
    END IF;
    
    -- PHASE 2: Performance Score Math Calculation Engine
    SELECT `role` INTO `v_user_role` FROM `employees` WHERE `id` = NEW.`employee_id`;
    SELECT `complexity_score`, `difficulty` INTO `v_complexity`, `v_difficulty` FROM `projects` WHERE `id` = NEW.`project_id`;

    IF `v_user_role` = 'Employee' THEN
        IF `v_difficulty` = 'High' THEN SET `v_difficulty_multiplier` = 3;
        ELSEIF `v_difficulty` = 'Medium' THEN SET `v_difficulty_multiplier` = 2;
        ELSE SET `v_difficulty_multiplier` = 1;
        END IF;

        IF NEW.`outcome_status` = 'Failed' THEN SET `v_calculated_score` = `v_complexity` * 2;
        ELSEIF NEW.`completion_status` = 'Completed_OnSchedule' AND NEW.`outcome_status` = 'Success' THEN SET `v_calculated_score` = (`v_complexity` * 10) * `v_difficulty_multiplier`;
        ELSEIF NEW.`completion_status` = 'Completed_Overdue' AND NEW.`outcome_status` = 'Success' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.80;
        ELSEIF NEW.`completion_status` = 'InProgress_OnSchedule' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.50;
        ELSEIF NEW.`completion_status` = 'InProgress_Overdue' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.20;
        END IF;

        INSERT INTO `contributions` (`employee_id`, `project_id`, `appraisal_period_id`, `contribution_score`)
        VALUES (NEW.`employee_id`, NEW.`project_id`, NEW.`appraisal_period_id`, `v_calculated_score`)
        ON DUPLICATE KEY UPDATE `contribution_score` = `v_calculated_score`;
    END IF;
END//


-- 2. Consolidated UPDATE Pipeline: locked vs active Verification + calculate Scoring 

CREATE TRIGGER `before_performance_update_pipeline`
BEFORE UPDATE ON `performance_records`
FOR EACH ROW
BEGIN
    DECLARE `v_period_status` VARCHAR(10);
    DECLARE `v_user_role` VARCHAR(20);
    DECLARE `v_complexity` INT;
    DECLARE `v_difficulty` VARCHAR(10);
    DECLARE `v_difficulty_multiplier` INT DEFAULT 1;
    DECLARE `v_calculated_score` DECIMAL(5,2) DEFAULT 0.00;
    
    -- PHASE 1: Security Validation - CHECKS IF THE PERIOD IS 'Locked'
    SELECT `status` INTO `v_period_status` 
    FROM `appraisal_periods` 
    WHERE `id` = OLD.`appraisal_period_id`;
    
    IF `v_period_status` = 'Locked' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Security Violation: Performance targets are locked for finalized historical periods.';
    END IF;
    
    -- PHASE 2: Performance Score Math Calculation Engine
    SELECT `role` INTO `v_user_role` FROM `employees` WHERE `id` = NEW.`employee_id`;
    SELECT `complexity_score`, `difficulty` INTO `v_complexity`, `v_difficulty` FROM `projects` WHERE `id` = NEW.`project_id`;

    IF `v_user_role` = 'Employee' THEN
        IF `v_difficulty` = 'High' THEN SET `v_difficulty_multiplier` = 3;
        ELSEIF `v_difficulty` = 'Medium' THEN SET `v_difficulty_multiplier` = 2;
        ELSE SET `v_difficulty_multiplier` = 1;
        END IF;

        IF NEW.`outcome_status` = 'Failed' THEN SET `v_calculated_score` = `v_complexity` * 2;
        ELSEIF NEW.`completion_status` = 'Completed_OnSchedule' AND NEW.`outcome_status` = 'Success' THEN SET `v_calculated_score` = (`v_complexity` * 10) * `v_difficulty_multiplier`;
        ELSEIF NEW.`completion_status` = 'Completed_Overdue' AND NEW.`outcome_status` = 'Success' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.80;
        ELSEIF NEW.`completion_status` = 'InProgress_OnSchedule' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.50;
        ELSEIF NEW.`completion_status` = 'InProgress_Overdue' THEN SET `v_calculated_score` = ((`v_complexity` * 10) * `v_difficulty_multiplier`) * 0.20;
        END IF;

        INSERT INTO `contributions` (`employee_id`, `project_id`, `appraisal_period_id`, `contribution_score`)
        VALUES (NEW.`employee_id`, NEW.`project_id`, NEW.`appraisal_period_id`, `v_calculated_score`)
        ON DUPLICATE KEY UPDATE `contribution_score` = `v_calculated_score`;
    END IF;
END//

DELIMITER ;


-- ============================================================================
-- VIEWS
-- ============================================================================
-- View 1: Functional Itemized Profile Ledger
CREATE VIEW `vw_individual_project_scores` AS
SELECT 
    ap.`id` AS `appraisal_period_id`,
    ap.`period_name`,
    e.`username`,
    e.`password`,
    e.`manager_id`, 
    e.`department_id`, 
    CONCAT(e.`first_name`, ' ', e.`last_name`) AS `employee_name`,
    p.`project_name`,
    e.`functional_title` AS `assigned_role`,
    p.`difficulty`,
    pr.`completion_status`,
    pr.`outcome_status`,
    c.`contribution_score` AS `individual_project_score`,
    CAST(
        (p.`complexity_score` * 10) * CASE p.`difficulty` 
            WHEN 'High' THEN 3 
            WHEN 'Medium' THEN 2 
            ELSE 1 
        END AS DECIMAL(5,2)
    ) AS `maximum_possible_project_score`,
    pr.`manager_review_notes`
FROM `contributions` c
JOIN `employees` e ON c.`employee_id` = e.`id`
JOIN `projects` p ON c.`project_id` = p.`id`
JOIN `appraisal_periods` ap ON c.`appraisal_period_id` = ap.`id`
JOIN `performance_records` pr ON (c.`employee_id` = pr.`employee_id` AND c.`project_id` = pr.`project_id` AND c.`appraisal_period_id` = pr.`appraisal_period_id`);


-- View 2: Forward structural parameters to the corporate aggregation interface
CREATE VIEW `vw_final_cycle_appraisal` AS
SELECT 
    vips.`appraisal_period_id`,
    vips.`period_name`,
    vips.`manager_id`,
    vips.`department_id`,
    vips.`employee_name`,
    SUM(vips.`individual_project_score`) AS `final_cumulative_score`,
    SUM(vips.`maximum_possible_project_score`) AS `total_possible_score`,
    CAST((SUM(vips.`individual_project_score`) / SUM(vips.`maximum_possible_project_score`)) * 100 AS DECIMAL(5,2)) AS `execution_efficiency_pct`,
    COUNT(vips.`project_name`) AS `total_concurrent_projects`
FROM `vw_individual_project_scores` vips
GROUP BY vips.`appraisal_period_id`, vips.`employee_name`, vips.`manager_id`, vips.`department_id`;

-- View 3: Portfolio Asset Delivery Health Report
CREATE VIEW `vw_department_project_execution` AS
SELECT 
    ap.`id` AS `appraisal_period_id`,
    ap.`period_name`,
    d.`department_name`,
    p.`project_name`,
    p.`difficulty`,
    pr.`completion_status`,
    pr.`outcome_status`,
    AVG(c.`contribution_score`) AS `team_average_performance_score`,
    -- Satisfies 1(a): Calculate the max baseline score for the project context
    CAST(
        (p.`complexity_score` * 10) * CASE p.`difficulty` 
            WHEN 'High' THEN 3 
            WHEN 'Medium' THEN 2 
            ELSE 1 
        END AS DECIMAL(5,2)
    ) AS `maximum_possible_team_score`,
    COUNT(DISTINCT pr.`employee_id`) AS `allocated_staff_count`
FROM `performance_records` pr
JOIN `employees` e ON pr.`employee_id` = e.`id`
JOIN `departments` d ON e.`department_id` = d.`id`
JOIN `projects` p ON pr.`project_id` = p.`id`
JOIN `contributions` c ON (pr.`employee_id` = c.`employee_id` AND pr.`project_id` = c.`project_id` AND pr.`appraisal_period_id` = c.`appraisal_period_id`)
JOIN `appraisal_periods` ap ON pr.`appraisal_period_id` = ap.`id`
GROUP BY ap.`id`, d.`department_name`, p.`id`, pr.`completion_status`, pr.`outcome_status`;

-- ============================================================================
-- STORED PROCEDURE using the created VIEWS
-- ============================================================================

DELIMITER //

CREATE PROCEDURE `GetEmployeeDashboard`(
    IN `p_username` VARCHAR(50),
    IN `p_password` VARCHAR(100),
    IN `p_appraisal_period_id` INT
)
BEGIN
    DECLARE `v_user_role` VARCHAR(20) DEFAULT NULL;
    DECLARE `v_user_id` INT DEFAULT NULL;
    DECLARE `v_user_dept` INT DEFAULT NULL;
    
    SELECT `role`, `id`, `department_id` INTO `v_user_role`, `v_user_id`, `v_user_dept`
    FROM `employees`
    WHERE `username` = `p_username` AND `password` = `p_password`;

    IF `v_user_role` = 'Employee' THEN
        -- Regular Employees only pull their matching credentials line
        SELECT `period_name`, `project_name`, `assigned_role`, `difficulty`, `completion_status`, `outcome_status`, `individual_project_score`, `maximum_possible_project_score`, `manager_review_notes`
        FROM `vw_individual_project_scores`
        WHERE `username` = `p_username` AND `password` = `p_password` AND `appraisal_period_id` = `p_appraisal_period_id`;

    ELSEIF `v_user_role` = 'Manager' THEN
        -- Satisfies Requirement #2: Show all individual itemized rows for their department with names
        SELECT `period_name`, `employee_name`, `project_name`, `assigned_role`, `difficulty`, `completion_status`, `outcome_status`, `individual_project_score`, `maximum_possible_project_score`, `manager_review_notes`
        FROM `vw_individual_project_scores`
        WHERE `department_id` = `v_user_dept` AND `appraisal_period_id` = `p_appraisal_period_id`
        ORDER BY `employee_name`;

    ELSEIF `v_user_role` = 'HR' THEN
        -- Satisfies Requirement #3: Global itemized access for cross-corporate reviews
        SELECT `period_name`, `employee_name`, `project_name`, `assigned_role`, `difficulty`, `completion_status`, `outcome_status`, `individual_project_score`, `maximum_possible_project_score`, `manager_review_notes`
        FROM `vw_individual_project_scores`
        WHERE `appraisal_period_id` = `p_appraisal_period_id`
        ORDER BY `department_id`, `employee_name`;
    END IF;
END//


CREATE PROCEDURE `GetSecuredCorporateDashboard`(
    IN `p_username` VARCHAR(50),
    IN `p_password` VARCHAR(100),
    IN `p_appraisal_period_id` INT,
    IN `p_dashboard_mode` VARCHAR(20) -- 'SUMMARY' (Efficiency KPI) or 'HEALTH' (Team Executions)
)
BEGIN
    DECLARE `v_user_role` VARCHAR(20) DEFAULT NULL;
    DECLARE `v_user_id` INT DEFAULT NULL;
    DECLARE `v_user_dept` INT DEFAULT NULL;
    
    SELECT `role`, `id`, `department_id` INTO `v_user_role`, `v_user_id`, `v_user_dept`
    FROM `employees`
    WHERE `username` = `p_username` AND `password` = `p_password`;

    -- Guard Gate: Employees are systematically rejected from corporate overview gateways
    IF `v_user_role` = 'Employee' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Access Denied: Employees do not possess clearance for corporate summary interfaces.';

    ELSEIF `v_user_role` = 'Manager' THEN
        IF `p_dashboard_mode` = 'SUMMARY' THEN
            -- Efficiency KPIs for department personnel
            SELECT `period_name`, `employee_name`, `final_cumulative_score`, `total_possible_score`, `execution_efficiency_pct`, `total_concurrent_projects`
            FROM `vw_final_cycle_appraisal`
            WHERE `appraisal_period_id` = `p_appraisal_period_id` AND `manager_id` = `v_user_id`
            ORDER BY `execution_efficiency_pct` DESC;
        ELSEIF `p_dashboard_mode` = 'HEALTH' THEN
            -- Operational portfolio delivery health for their unit (with new max score)
            SELECT `period_name`, `department_name`, `project_name`, `difficulty`, `completion_status`, `outcome_status`, `team_average_performance_score`, `maximum_possible_team_score`, `allocated_staff_count`
            FROM `vw_department_project_execution`
            WHERE `appraisal_period_id` = `p_appraisal_period_id`
              AND `department_name` = (SELECT `department_name` FROM `departments` WHERE `id` = `v_user_dept`)
            ORDER BY `team_average_performance_score` DESC;
        END IF;

    ELSEIF `v_user_role` = 'HR' THEN
        IF `p_dashboard_mode` = 'SUMMARY' THEN
            -- Global corporate personnel ranking leaderboard
            SELECT `period_name`, `employee_name`, `final_cumulative_score`, `total_possible_score`, `execution_efficiency_pct`, `total_concurrent_projects`
            FROM `vw_final_cycle_appraisal`
            WHERE `appraisal_period_id` = `p_appraisal_period_id`
            ORDER BY `execution_efficiency_pct` DESC;
        ELSEIF `p_dashboard_mode` = 'HEALTH' THEN
            -- Global cross-department asset roadmap tracking
            SELECT `period_name`, `department_name`, `project_name`, `difficulty`, `completion_status`, `outcome_status`, `team_average_performance_score`, `maximum_possible_team_score`, `allocated_staff_count`
            FROM `vw_department_project_execution`
            WHERE `appraisal_period_id` = `p_appraisal_period_id`
            ORDER BY `department_name`, `team_average_performance_score` DESC;
        END IF;
    END IF;
END//

DELIMITER ;

-- ============================================================================
-- STEP 1: INITIAL SEEDING (Keep ALL periods 'Active' initially)
-- ============================================================================

INSERT INTO `departments` (`id`, `department_name`) VALUES
(1, 'Quality Assurance & V&V'),
(2, 'Product Development & Analytics'),
(3, 'IRAD'),
(4, 'HR');

-- CRITICAL: Set historical periods to 'Active' so the trigger lets data pass
INSERT INTO `appraisal_periods` (`id`, `period_name`, `start_date`, `end_date`, `status`) VALUES
(1, '2025_H1', '2025-01-01', '2025-06-30', 'Active'),
(2, '2025_H2', '2025-07-01', '2025-12-31', 'Active'),
(3, '2026_Q1', '2026-01-01', '2026-03-31', 'Active'),
(4, '2026_Q2', '2026-04-01', '2026-06-30', 'Active');

INSERT INTO `employees` (`id`, `first_name`, `last_name`, `email`, `username`, `password`, `role`, `functional_title`, `department_id`, `manager_id`, `hire_date`) VALUES
(1, 'John', 'Doe', 'j.doe@company.com', 'jdoe', 'john2026', 'Manager', 'Manager', 1, NULL, '2020-01-15'),
(2, 'David', 'Kemp', 'd.kemp@company.com', 'dkemp', 'david2026', 'Manager', 'Manager', 2, NULL, '2019-05-12'),
(3, 'Sarah', 'Jenkins', 's.jenkins@company.com', 'sjenkins', 'pass123', 'HR', 'HR Specialist', 4, NULL, '2021-08-20'),
(4, 'Alice', 'Smith', 'a.smith@company.com', 'asmith', 'alice2026', 'Employee', 'Sr. QAE', 1, 1, '2022-03-01'),
(5, 'Robert', 'Lee', 'r.lee@company.com', 'rlee', 'rose2026', 'Employee', 'Associate QAE', 1, 1, '2024-06-15'),
(6, 'Michael', 'Chang', 'm.chang@company.com', 'mchang', 'mike2026', 'Employee', 'Sr. SWE', 2, 2, '2021-11-10'),
(7, 'Elena', 'Rostova', 'e.rostova@company.com', 'erostova', 'elena2026', 'Employee', 'Staff SWE', 2, 2, '2020-04-22'),
(8, 'Tariq', 'Mansoor', 't.mansoor@company.com', 'tmansoor', 'tariq2026', 'Employee', 'Associate Researcher', 2, 2, '2025-01-10');

INSERT INTO `projects` (`id`, `project_name`, `difficulty`, `complexity_score`, `start_date`, `end_date`) VALUES
(1, 'Next-Gen Infusion Pump V&V', 'High', 9, '2025-01-10', '2026-04-15'),
(2, 'Glucose Monitor UI Remediation', 'Medium', 6, '2026-01-01', NULL),
(3, 'Internal Tooling Automation', 'Low', 3, '2025-11-01', '2026-03-20'),
(4, 'Biocompatibility Sterility Phase II', 'High', 8, '2026-01-15', NULL),
(5, 'Cardiology Telemetry API Framework', 'High', 7, '2025-06-01', '2026-03-01'),
(6, 'Laboratory Information Management System Upgrade', 'Medium', 5, '2025-09-01', NULL),
(7, 'Automated Regression Suite Optimization', 'Low', 4, '2025-01-01', '2025-06-01'),
(8, 'Bio-Telemetry Telemetry Validation', 'High', 9, '2026-04-01', NULL),
(9, 'Legacy Core Patch Integration', 'Medium', 5, '2026-04-01', NULL);

INSERT INTO `project_assignments` (`employee_id`, `project_id`) VALUES
(4, 1), (4, 2), (5, 4), (6, 5),
(6, 3), (7, 6), (7, 1), (8, 7),
(4, 8), (6, 8), (7, 9);


-- ============================================================================
-- STEP 2: COMPILE TRIGGERS & INJECT PERFORMANCE RECORDS
-- ============================================================================
-- (Insert your consolidated triggers here so they fire dynamically during the next statement)

INSERT INTO `performance_records` (`employee_id`, `project_id`, `appraisal_period_id`, `completion_status`, `outcome_status`, `manager_review_notes`) VALUES
-- 2025_H1 Archive 
(4, 1, 1, 'InProgress_OnSchedule', 'N/A', 'Historical Record H1: Alice tracking on baseline protocols.'),
-- 2025_H2 Archive 
(4, 1, 2, 'InProgress_Overdue', 'N/A', 'Historical Record H2: Slower traction due to documentation backlog.'),
-- 2026_Q1 Active Transactions
(4, 1, 3, 'Completed_Overdue', 'Success', 'Bypassed environmental blocks to wrap final verification protocol steps safely.'),
(4, 2, 3, 'Completed_OnSchedule', 'Success', 'Successfully delivered standard UI test suites on time.'),
(5, 4, 3, 'InProgress_OnSchedule', 'N/A', 'Robert progressing smoothly through active compliance runs.'),
(6, 5, 3, 'Completed_OnSchedule', 'Success', 'Michael completed architecture design for the high-throughput telemetry API.'),
(6, 3, 3, 'Completed_OnSchedule', 'Failed', 'Deployment package execution broke standard system regression layers.'),
(7, 1, 3, 'Completed_Overdue', 'Success', 'Elena joined the initiative to help Alice finalize high-complexity metrics coverage.'),
-- 2026_Q2 Active Transactions
(4, 8, 4, 'Completed_OnSchedule', 'Success', 'Alice delivered exceptional validation protocols ahead of the compliance deadline.'),
(6, 8, 4, 'Completed_Overdue', 'Failed', 'Michael missed the integration milestone and build deployment introduced regression faults.'),
(7, 9, 4, 'InProgress_OnSchedule', 'N/A', 'Elena is making steady progress on patch baselines; tracking well against milestones.');


-- ============================================================================
-- STEP 3: LOCK HISTORY (Seal the state machine)
-- ============================================================================
-- Once all tables are populated and the math trigger has run, freeze the old timelines securely.

UPDATE `appraisal_periods` 
SET `status` = 'Locked' 
WHERE `id` IN (1, 2);