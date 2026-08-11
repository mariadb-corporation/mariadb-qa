SET sql_mode=ORACLE;
CREATE PACKAGE emp_pkg AS TYPE emp_rec IS RECORD (id INT); FUNCTION get_emp(p_id INT) RETURN emp_rec; END;
CREATE PACKAGE BODY emp_pkg AS FUNCTION get_emp(p_id INT) RETURN emp_pkg.emp_rec AS v emp_pkg.emp_rec; BEGIN v.id := p_id; RETURN v; END; END;
CREATE PROCEDURE show_emp AS v emp_pkg.emp_rec; BEGIN v := emp_pkg.get_emp(7); SELECT v.id AS id; END;
CALL show_emp;

SET sql_mode=ORACLE;
CREATE OR REPLACE PACKAGE emp_pkg AS TYPE emp_rec IS RECORD (id INT); PROCEDURE get_emp(p_id INT); END;
CREATE OR REPLACE PACKAGE BODY emp_pkg AS PROCEDURE get_emp(p_id INT) AS v emp_pkg.emp_rec; BEGIN NULL; END; END;
CREATE OR REPLACE PROCEDURE show_emp AS BEGIN emp_pkg.get_emp(7); END;
CALL show_emp;
