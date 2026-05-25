-- ============================================================================
-- DATABASE INITIALIZATION
-- ============================================================================
CREATE DATABASE IF NOT EXISTS `employee_performance`;
USE `employee_performance`;

-- ============================================================================
-- DEPARTMENTS TABLE
-- ============================================================================
CREATE TABLE `departments` (
    `id` INT AUTO_INCREMENT,
    `department_name` VARCHAR(100) NOT NULL UNIQUE,
    PRIMARY KEY (`id`)
);

-- ============================================================================
-- APPRAISAL TABLE - Appraisal Periods Configuration Table
-- Adjust appraisal period frequency according to companies' policy:
-- E.g., Annually => '2025_Annual' or quarterly => '2025_Q1'
-- ============================================================================
CREATE TABLE `appraisal_periods` (
    `id` INT AUTO_INCREMENT,
    `period_name` VARCHAR(50) NOT NULL UNIQUE, -- e.g., '2025_Annual', '2026_Q1'
    `start_date` DATE NOT NULL,
    `end_date` DATE NOT NULL,
    `status` ENUM('Active', 'Locked') DEFAULT 'Active',
    PRIMARY KEY (`id`),
    CONSTRAINT `chk_date_chronology` CHECK (`end_date` > `start_date`)
);

-- ============================================================================
-- EMPLOYEES TABLE
-- ============================================================================
CREATE TABLE `employees` (
    `id` INT AUTO_INCREMENT,
    `first_name` VARCHAR(50) NOT NULL,
    `last_name` VARCHAR(50) NOT NULL,
    `email` VARCHAR(100) NOT NULL UNIQUE,
    `username` VARCHAR(50) NOT NULL UNIQUE,
    `password` VARCHAR(100) NOT NULL,
    -- Controls system access level (stored procedures views access)
    `role` ENUM('Employee', 'Manager', 'HR') NOT NULL DEFAULT 'Employee',
    `functional_title` ENUM(
        'Manager', 'HR Specialist',
        'Associate SWE', 'Sr. SWE', 'Staff SWE',
        'Associate QAE', 'Sr. QAE', 'Staff QAE',
        'Associate Researcher', 'Sr. Researcher', 'Staff Researcher'
    ) NOT NULL,
    `department_id` INT,
    `manager_id` INT,
    `hire_date` DATE NOT NULL,
    PRIMARY KEY (`id`),
    FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE SET NULL,
    FOREIGN KEY (`manager_id`) REFERENCES `employees`(`id`) ON DELETE SET NULL,

    -- Fields validations (Department 4 is HR). Guarantees organizational structural alignment
    CONSTRAINT `chk_department_role_alignment` CHECK (
        (`role` = 'HR' AND `department_id` = 4 AND `functional_title` = 'HR Specialist') OR
        (`role` = 'Manager' AND `functional_title` = 'Manager') OR
        (`role` = 'Employee' AND `functional_title` NOT IN ('Manager', 'HR Specialist'))
    )
);

-- ============================================================================
-- PROJECTS TABLE
-- ============================================================================
CREATE TABLE `projects` (
    `id` INT AUTO_INCREMENT,
    `project_name` VARCHAR(150) NOT NULL UNIQUE,
    `difficulty` ENUM('Low', 'Medium', 'High') NOT NULL,
    `complexity_score` INT NOT NULL,
    `start_date` DATE NOT NULL,
    `end_date` DATE DEFAULT NULL, -- Nullable to allow ongoing/active projects
    PRIMARY KEY (`id`),
    CONSTRAINT `chk_complexity` CHECK (`complexity_score` BETWEEN 1 AND 10),
    CONSTRAINT `chk_project_dates` CHECK (`end_date` IS NULL OR `end_date` >= `start_date`)
);

-- ============================================================================
-- PROJECT ASSIGNMENTS TABLE (Many-to-Many Bridge between projects and employees)
-- ============================================================================
CREATE TABLE `project_assignments` (
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    PRIMARY KEY (`employee_id`, `project_id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`),
    FOREIGN KEY (`project_id`) REFERENCES `projects` (`id`)
);

-- ============================================================================
-- PERFORMANCE RECORDS TABLE
-- ============================================================================
CREATE TABLE `performance_records` (
    `id` INT AUTO_INCREMENT,
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    `appraisal_period_id` INT NOT NULL,
    `completion_status` ENUM('InProgress_OnSchedule', 'InProgress_Overdue', 'Paused', 'Completed_OnSchedule', 'Completed_Overdue') NOT NULL,
    `outcome_status` ENUM('Success', 'Failed', 'N/A') DEFAULT 'N/A',
    `manager_review_notes` TEXT DEFAULT NULL,
    `employee_self_notes` TEXT DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_employee_project_cycle` (`employee_id`, `project_id`, `appraisal_period_id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`),
    FOREIGN KEY (`project_id`) REFERENCES `projects` (`id`),
    FOREIGN KEY (`appraisal_period_id`) REFERENCES `appraisal_periods` (`id`)
);

-- ============================================================================
-- CONTRIBUTIONS TABLE (With driven contribution_score Log), and is considered live for existing relationship between
-- an employee and a project, so if the project extended to two or three performance cycles to complete, the 
-- score field in employee/project ids record should be updated per the employee's project performance in the 
-- current latest performance cycle/period
-- ============================================================================
CREATE TABLE `contributions` (
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    `appraisal_period_id` INT NOT NULL,
    `contribution_score` DECIMAL(5,2) NOT NULL,
    PRIMARY KEY (`employee_id`, `project_id`, `appraisal_period_id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`) ON DELETE CASCADE,
    FOREIGN KEY (`project_id`) REFERENCES `projects` (`id`) ON DELETE CASCADE,
    FOREIGN KEY (`appraisal_period_id`) REFERENCES `appraisal_periods` (`id`) ON DELETE RESTRICT
);

