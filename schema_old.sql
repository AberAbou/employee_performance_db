-- ============================================================================
-- DATABASE INITIALIZATION
-- ============================================================================
CREATE DATABASE IF NOT EXISTS `employee_performance`;
USE `employee_performance`;

-- ============================================================================
-- 1. DEPARTMENTS TABLE
-- ============================================================================
CREATE TABLE `departments` (
    `id` INT AUTO_INCREMENT,
    `department_name` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`id`)
);

-- ============================================================================
-- 2. EMPLOYEES TABLE (With plain-text authentication credentials)
-- ============================================================================
CREATE TABLE `employees` (
    `id` INT AUTO_INCREMENT,
    `first_name` VARCHAR(50) NOT NULL,
    `last_name` VARCHAR(50) NOT NULL,
    `email` VARCHAR(100) NOT NULL,
    `username` VARCHAR(50) NOT NULL,
    `password` VARCHAR(100) NOT NULL,
    
    -- System access level
    `role` ENUM('Employee', 'Manager', 'HR') NOT NULL DEFAULT 'Employee',
    
    -- Professional track engineering designation
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
    UNIQUE (`email`),
    UNIQUE (`username`),
    FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE SET NULL,
    FOREIGN KEY (`manager_id`) REFERENCES `employees`(`id`) ON DELETE SET NULL,

    -- Business logic integrity validation (Department 4 is HR)
    CONSTRAINT `chk_department_role_alignment` CHECK (
        (`role` = 'HR' AND `department_id` = 4 AND `functional_title` = 'HR Specialist') OR
        (`role` = 'Manager' AND `functional_title` = 'Manager') OR
        (`role` = 'Employee' AND `functional_title` NOT IN ('Manager', 'HR Specialist'))
    )
) ENGINE=InnoDB;

-- ============================================================================
-- 3. PROJECTS TABLE
-- ============================================================================
CREATE TABLE `projects` (
    `id` INT AUTO_INCREMENT,
    `project_name` VARCHAR(150) NOT NULL,
    `difficulty` ENUM('Low', 'Medium', 'High') NOT NULL,
    `complexity_score` INT NOT NULL,
    `start_date` DATE NOT NULL,
    `end_date` DATE,
    PRIMARY KEY (`id`),
    CONSTRAINT `chk_complexity` CHECK (`complexity_score` BETWEEN 1 AND 10)
);

-- ============================================================================
-- 4. PROJECT ASSIGNMENTS TABLE (Many-to-Many Bridge)
-- ============================================================================
CREATE TABLE `project_assignments` (
    `id` INT AUTO_INCREMENT,
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    `assigned_role` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE (`employee_id`, `project_id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`),
    FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) 
);

-- ============================================================================
-- 5. PERFORMANCE RECORDS TABLE
-- ============================================================================
CREATE TABLE `performance_records` (
    `id` INT AUTO_INCREMENT,
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    `completion_status` ENUM('InProgress', 'Paused', 'Completed') NOT NULL,
    `outcome_status` ENUM('Success', 'Failed', 'N/A') DEFAULT 'N/A',
    `manager_review_notes` TEXT,
    `employee_self_notes` TEXT,
    `review_year` YEAR NOT NULL,
    PRIMARY KEY (`id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`),
    FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) 
);

-- ============================================================================
-- 6. CONTRIBUTIONS TABLE (Target-Driven Score Log), and is considered live for existing relationship between
-- an employee and a project, so if the project extended to two or three performance cycles to complete, the 
-- score field in employee/project ids record should be updated per the employee's project performance in the 
-- current latest performance cycle/period
-- ============================================================================
CREATE TABLE `contributions` (
    `id` INT AUTO_INCREMENT,
    `employee_id` INT NOT NULL,
    `project_id` INT NOT NULL,
    `contribution_score` DECIMAL(5,2) DEFAULT 0.00,
    `last_calculated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE (`employee_id`, `project_id`),
    FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ,
    FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) 
);

