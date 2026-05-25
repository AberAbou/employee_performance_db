-- ============================================================================
-- PERFORMANCE & OPTIMIZATION INDEXES
-- ============================================================================
CREATE INDEX `idx_perf_year_emp` ON `performance_records` (`review_year`, `employee_id`);
CREATE INDEX `idx_assignment_lookup` ON `project_assignments` (`project_id`, `employee_id`);

-- ============================================================================
-- PERFORMANCE records INSERT TRIGGER
-- ============================================================================


-- 1. Create an updated, dual-purpose trigger that runs on AFTER INSERT
DELIMITER //


CREATE TRIGGER `after_performance_insert`
AFTER INSERT ON `performance_records`
FOR EACH ROW
BEGIN
    DECLARE `v_difficulty_multiplier` INT DEFAULT 1;
    DECLARE `v_complexity` INT DEFAULT 1;
    DECLARE `v_final_score` DECIMAL(5,2) DEFAULT 0.00;
    DECLARE `v_employee_role` VARCHAR(20);

    -- 1. Extract the organizational role of the target employee row
    SELECT `role` INTO `v_employee_role`
    FROM `employees`
    WHERE `id` = NEW.`employee_id`;

    -- 2. Execute calculation logic exclusively for standard engineering profiles
    IF `v_employee_role` = 'Employee' THEN
        SELECT `complexity_score`, 
               CASE `difficulty` 
                   WHEN 'High' THEN 3 
                   WHEN 'Medium' THEN 2 
                   ELSE 1 
               END
        INTO `v_complexity`, `v_difficulty_multiplier`
        FROM `projects` 
        WHERE `id` = NEW.`project_id`;

        IF NEW.`completion_status` = 'Completed' AND NEW.`outcome_status` = 'Success' THEN
            SET `v_final_score` = (`v_complexity` * 10) * `v_difficulty_multiplier`;
        ELSEIF NEW.`completion_status` = 'Completed' AND NEW.`outcome_status` = 'Failed' THEN
            SET `v_final_score` = (`v_complexity` * 2);
        ELSE
            SET `v_final_score` = 0.00;
        END IF;

        -- 3. Seamlessly pipeline the calculated score into the contributions tracking table
        INSERT INTO `contributions` (`employee_id`, `project_id`, `contribution_score`)
        VALUES (NEW.`employee_id`, NEW.`project_id`, `v_final_score`)
        ON DUPLICATE KEY UPDATE `contribution_score` = `v_final_score`;-- If the employee and project id already exists in the table, just update the score
    END IF;
END//

DELIMITER ;

-- ============================================================================
-- INSERTION SEEDING
-- ============================================================================

-- 1. POPULATE DEPARTMENTS
INSERT INTO `departments` (`department_name`) VALUES 
('IRAD'),
('Product Development & Analytics'),
('Quality Assurance & V&V'),
('Human Resources (HR)');

-- 2. POPULATE EMPLOYEES (Expanded Matrix with explicit hierarchy links)
INSERT INTO `employees` (`first_name`, `last_name`, `email`, `username`, `password`, `role`, `functional_title`, `department_id`, `manager_id`, `hire_date`) VALUES 
-- CEO
('Marcus', 'Aurelius', 'm.aurelius@company.com', 'maurelius', 'ceo2026', 'Manager', 'Manager', NULL, NULL, '2018-01-01');

-- Step 2b: Insert Functional Leaders and HR 
INSERT INTO `employees` (`first_name`, `last_name`, `email`, `username`, `password`, `role`, `functional_title`, `department_id`, `manager_id`, `hire_date`) VALUES 
('Sarah', 'Jenkins', 's.jenkins@company.com', 'sjenkins', 'pass123', 'HR', 'HR Specialist', 4, 1, '2020-03-15'),
('John', 'Doe', 'j.doe@company.com', 'jdoe', 'john2026', 'Manager', 'Manager', 2, 1, '2022-06-01'),
('David', 'Kemp', 'd.kemp@company.com', 'dkemp', 'david2026', 'Manager', 'Manager', 3, 1, '2019-10-05');

-- Step 2c: Insert developers and software engineers (Generates IDs = 5 through 9)
INSERT INTO `employees` (`first_name`, `last_name`, `email`, `username`, `password`, `role`, `functional_title`, `department_id`, `manager_id`, `hire_date`) VALUES 
('Alice', 'Smith', 'a.smith@company.com', 'asmith', 'alice2026', 'Employee', 'Sr. QAE', 3, 4, '2023-01-10'),          -- QA Dept (under David ID=4)
('Robert', 'Lee', 'r.lee@company.com', 'rlee', 'robert2026', 'Employee', 'Associate QAE', 3, 4, '2021-11-20'),     -- QA Dept (under David ID=4)
('Michael', 'Chang', 'm.chang@company.com', 'mchang', 'mike2026', 'Employee', 'Sr. SWE', 2, 3, '2024-02-15'),       -- Dev Dept (under John ID=3)
('Elena', 'Rostova', 'e.rostova@company.com', 'erostova', 'elena2026', 'Employee', 'Staff SWE', 2, 3, '2023-08-22'),   -- Dev Dept (under John ID=3)
('Tariq', 'Mansoor', 't.mansoor@company.com', 'tmansoor', 'tariq2026', 'Employee', 'Associate Researcher', 1, 1, '2025-01-12'); -- IRAD Dept (under Marcus ID=1)

-- ============================================================================
-- 3. POPULATE PROJECTS (IDs auto-generate 1 through 8)
-- ============================================================================
INSERT INTO `projects` (`project_name`, `difficulty`, `complexity_score`, `start_date`, `end_date`) VALUES 
('Next-Gen Infusion Pump V&V', 'High', 9, '2025-01-15', '2025-12-20'),
('Glucose Monitor UI Remediation', 'Medium', 6, '2025-03-01', '2025-11-15'),
('Internal Tooling Automation', 'Low', 3, '2025-06-01', '2025-08-30'),
('Biocompatibility Sterility Phase II', 'High', 8, '2025-09-01', NULL),
('Cardiology Telemetry API Framework', 'High', 7, '2025-02-10', '2025-10-05'),
('Laboratory Information Management System Upgrade', 'Medium', 5, '2025-04-12', '2025-11-30'),
('Automated Regression Suite Optimization', 'Low', 4, '2025-07-15', '2025-09-15'),
('EU MDR Clinical Data Migration', 'High', 9, '2025-10-01', NULL);

-- ============================================================================
-- 4. POPULATE PROJECT ASSIGNMENTS (Comments completely removed)
-- ============================================================================
INSERT INTO `project_assignments` (`employee_id`, `project_id`, `assigned_role`) VALUES 
(3, 1, 'Lead Systems Engineer'),
(5, 1, 'Senior QA Consultant'),
(5, 2, 'Human Factors Engineer'),
(3, 3, 'Automation Scripting QA'),
(6, 4, 'Junior QA Engineer'),
(7, 5, 'SR Programmer'),
(8, 6, 'Data Analyst'),
(8, 1, 'Verification Test Engineer'),
(4, 6, 'IT Systems Analyst Specialist'),
(9, 7, 'IRAD Research Associate'),
(6, 8, 'Compliance Auditing Specialist'),
(7, 3, 'Python Developer Assistant');

-- ============================================================================
-- 5. POPULATE PERFORMANCE RECORDS (Fires Score Engine Triggers Automatically)
-- ============================================================================
INSERT INTO `performance_records` (`employee_id`, `project_id`, `completion_status`, `outcome_status`, `manager_review_notes`, `employee_self_notes`, `review_year`) VALUES 
(5, 1, 'Completed', 'Success', 'Exceeded all verification protocols under strict timeline.', 'Successfully managed traceability matrices.', 2025),
(5, 2, 'Completed', 'Failed', 'Missed core usability validation deadlines set by regulatory body.', 'Encountered unexpected edge cases in UI design changes.', 2025),
(3, 3, 'Completed', 'Success', 'Delivered automated framework ahead of schedule.', 'Constructed robust test harnesses.', 2025),
(6, 4, 'InProgress', 'N/A', 'Audit preparation currently tracking green.', 'Reviewing active submissions.', 2025),
(7, 5, 'Completed', 'Success', 'Architecture handles payload spikes flawlessly.', 'Developed optimal index structures for telemetry storage.', 2025),
(8, 6, 'Completed', 'Success', 'System upgrade passed data integrity requirements.', 'Executed standard IQ/OQ steps smoothly.', 2025),
(8, 1, 'Completed', 'Success', 'Provided comprehensive scripts that decreased manual cycles.', 'Contributed 45 test verification modules.', 2025),
(4, 6, 'Completed', 'Failed', 'Server configuration deployment caused extended lab downtime.', 'Encountered legacy driver incompatibility blocks.', 2025),
(9, 7, 'Completed', 'Success', 'Reduced Jenkins execution pipeline execution timelines by 30%.', 'Optimized multi-stage docker-compose build processes.', 2025),
(6, 8, 'InProgress', 'N/A', 'Initial scoping and technical gap assessment completed.', 'Compiled high-level regulatory assessment documentation.', 2025),
(7, 3, 'Completed', 'Success', 'Aided framework completion ahead of schedule.', 'Wrote core integration helper files.', 2025);

-- ============================================================================
-- VIEWS
-- ============================================================================
-- View A: Dashboard for viewing performance
CREATE VIEW `vw_my_performance_dashboard` AS
SELECT 
    e.`username`,
    e.`password`,
    e.`functional_title`, 
    pr.`review_year`,
    p.`project_name`,
    pa.`assigned_role`,
    p.`difficulty`,
    pr.`completion_status`,
    pr.`outcome_status`,
    c.`contribution_score`,
    pr.`manager_review_notes`
FROM `performance_records` pr
JOIN `projects` p ON pr.`project_id` = p.`id`
JOIN `project_assignments` pa ON (pr.`employee_id` = pa.`employee_id` AND pr.`project_id` = pa.`project_id`)
JOIN `contributions` c ON (pr.`employee_id` = c.`employee_id` AND pr.`project_id` = c.`project_id`)
JOIN `employees` e ON pr.`employee_id` = e.`id`;


-- View B: HR Corporate Calibration View for or HR and Managers only
DROP VIEW IF EXISTS `vw_hr_anonymized_analytics`;
CREATE VIEW `vw_hr_anonymized_analytics` AS
SELECT 
    d.`department_name`,
    p.`difficulty`,
    pr.`completion_status`,
    pr.`outcome_status`,
    AVG(c.`contribution_score`) AS `average_score_metric`,
    COUNT(pr.`id`) AS `total_evaluated_projects`
FROM `performance_records` pr
JOIN `employees` e ON pr.`employee_id` = e.`id`
JOIN `departments` d ON e.`department_id` = d.`id`
JOIN `projects` p ON pr.`project_id` = p.`id`
JOIN `contributions` c ON (pr.`employee_id` = c.`employee_id` AND p.`id` = c.`project_id`)
GROUP BY d.`department_name`, p.`difficulty`, pr.`completion_status`, pr.`outcome_status`;


-- ============================================================================
-- STORED PROCEDURE using the created VIEWS
-- ============================================================================

DELIMITER //


CREATE PROCEDURE `GetEmployeeDashboard`(
    IN `p_username` VARCHAR(50),
    IN `p_password` VARCHAR(100)
)
BEGIN
    DECLARE `v_user_role` VARCHAR(20) DEFAULT NULL;
    DECLARE `v_employee_id` INT DEFAULT NULL;
    
    -- Authenticate and capture operational properties
    SELECT `role`, `id` INTO `v_user_role`, `v_employee_id`
    FROM `employees`
    WHERE `username` = `p_username` AND `password` = `p_pdropassword`;

    -- CASE 1: HR and Managers review aggregate data vectors
    IF `v_user_role` IN ('HR', 'Manager') THEN
        SELECT 
            `department_name`,
            `difficulty`,
            `completion_status`,
            `outcome_status`,
            `average_score_metric`,
            `total_evaluated_projects`
        FROM `vw_hr_anonymized_analytics`;

    -- CASE 2: Regular Employees can view only their personal logs
    ELSEIF `v_user_role` = 'Employee' THEN
        SELECT 
            `review_year`,
            `project_name`,
            `assigned_role`,
            `difficulty`,
            `completion_status`,
            `outcome_status`,
            `contribution_score`,
            `manager_review_notes`
        FROM `vw_my_performance_dashboard`
        WHERE `username` = `p_username` 
          AND `password` = `p_password`;
    END IF;
END//




CREATE PROCEDURE `GetSecuredCorporateDashboard`(
    IN `p_username` VARCHAR(50),
    IN `p_password` VARCHAR(100)
)
BEGIN
    DECLARE `v_user_role` VARCHAR(20) DEFAULT NULL;
    
    -- Authenticate the operating user and check their structural access role
    SELECT `role` INTO `v_user_role`
    FROM `employees`
    WHERE `username` = `p_username` AND `password` = `p_password`;

    -- SECURITY GATE: Only allow execution to proceed if the user is HR or a Manager
    IF `v_user_role` IN ('HR', 'Manager') THEN
        SELECT 
            `username`,
            `functional_title`,
            `review_year`,
            `project_name`,
            `assigned_role`,
            `difficulty`,
            `completion_status`,
            `outcome_status`,
            `contribution_score`,
            `manager_review_notes`
        FROM `vw_my_performance_dashboard`
        ORDER BY `review_year` DESC, `username` ASC;
    END IF;
END//

DELIMITER ;
