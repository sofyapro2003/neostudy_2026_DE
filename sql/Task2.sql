CREATE SCHEMA DM;

CREATE TABLE IF NOT EXISTS dm.dm_account_turnover_f (
	on_date DATE,
	account_rk NUMERIC,
	credit_amount NUMERIC(23,8),
	credit_amount_rub NUMERIC(23,8), 
	debet_amount NUMERIC(23,8), 
	debet_amount_rub NUMERIC(23,8) 
);

CREATE TABLE IF NOT EXISTS dm.dm_account_balance_f (
	on_date DATE,
	account_rk NUMERIC,
	balance_out NUMERIC(23,8),
	balance_out_rub NUMERIC(23,8) 
);


CREATE OR REPLACE PROCEDURE ds.fill_account_turnover_f (i_OnDate DATE)
AS $$
DECLARE 
	r RECORD;

	i_credit_amount NUMERIC(23,8) DEFAULT 0;
	i_credit_amount_rub NUMERIC(23,8) DEFAULT 0;
	i_debet_amount NUMERIC(23,8) DEFAULT 0;
	i_debet_amount_rub NUMERIC(23,8) DEFAULT 0;

	proc_start TIMESTAMPTZ;
	proc_end TIMESTAMPTZ;
	msg TEXT DEFAULT 'Расчет витрины dm.dm_account_turnover_f';
	err_code TEXT;
	err_msg TEXT;
BEGIN
	
	proc_start := now();

	DELETE FROM dm.dm_account_turnover_f 
	WHERE on_date = $1;

	FOR r IN
		SELECT mad.*, COALESCE(merd.reduced_cource, 1) AS currency
		FROM ds.md_account_d mad LEFT JOIN ds.md_exchange_rate_d merd 
								 ON mad.currency_rk = merd.currency_rk
								 AND ($1 BETWEEN merd.data_actual_date AND merd.data_actual_end_date)
		WHERE $1 BETWEEN mad.data_actual_date AND mad.data_actual_end_date
	LOOP	
		
		SELECT COALESCE(SUM(credit_amount), 0) INTO i_credit_amount
		FROM ds.ft_posting_f
		WHERE r.account_rk = credit_account_rk 
		AND oper_date = $1;
	
		i_credit_amount_rub := i_credit_amount * r.currency;
		
		SELECT COALESCE(SUM(debet_amount), 0) INTO i_debet_amount
		FROM ds.ft_posting_f
		WHERE r.account_rk = debet_account_rk 
		AND oper_date = $1;
	
		i_debet_amount_rub := i_debet_amount * r.currency;
	
		IF i_credit_amount <> 0 OR i_debet_amount <> 0 THEN
			INSERT INTO dm.dm_account_turnover_f(on_date, account_rk, credit_amount, credit_amount_rub, debet_amount, debet_amount_rub)
			VALUES ($1, r.account_rk, i_credit_amount, i_credit_amount_rub, i_debet_amount, i_debet_amount_rub);
		END IF;
	END LOOP;

	proc_end := now();
	
	INSERT INTO logs.logs_table (log_start_time, log_end_time, log_message)
    VALUES (proc_start, proc_end, msg);

	EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS 
            err_msg := message_text,
            err_code := returned_sqlstate;
        
	    INSERT INTO logs.logs_table (log_start_time, log_end_time, log_message, log_err_code, log_err_msg)
	    VALUES (proc_start, proc_end, msg, err_code, err_msg);
END;
$$
LANGUAGE plpgsql;


SELECT * FROM dm.dm_account_turnover_f;
SELECT * FROM logs.logs_table;
-- CALL ds.fill_account_turnover_f('2018-01-09');


-- заполнение витрины данными за 31.12.2017
INSERT INTO dm.dm_account_balance_f(on_date, account_rk, balance_out, balance_out_rub)
	SELECT COALESCE(fbf.on_date, '2017-12-31'::date), 
		   mad.account_rk, 
		   COALESCE(fbf.balance_out), 
		   COALESCE(fbf.balance_out, 0) * COALESCE(merd.reduced_cource, 1)
	FROM ds.md_account_d mad LEFT JOIN ds.ft_balance_f fbf ON mad.account_rk = fbf.account_rk 
							 LEFT JOIN ds.md_exchange_rate_d merd 
							 ON fbf.currency_rk = merd.currency_rk 
							 AND fbf.on_date BETWEEN merd.data_actual_date AND merd.data_actual_end_date
	WHERE fbf.on_date = '2017-12-31'::date;
 

CREATE OR REPLACE PROCEDURE ds.fill_account_balance_f (i_OnDate DATE)
AS $$
DECLARE 	
	proc_start TIMESTAMPTZ;
	proc_end TIMESTAMPTZ;
	msg TEXT DEFAULT 'Расчет витрины dm.dm_account_balance_f';
	err_code TEXT;
	err_msg TEXT;
BEGIN
	
	proc_start := now();

	DELETE FROM dm.dm_account_balance_f 
	WHERE on_date = $1;

	INSERT INTO dm.dm_account_balance_f(on_date, account_rk, balance_out, balance_out_rub)
		SELECT $1,
			   mad.account_rk,
        	   COALESCE(dabf.balance_out, 0) + 
	           CASE mad.char_type
	               WHEN 'А' THEN COALESCE(datf.debet_amount, 0) - COALESCE(datf.credit_amount, 0)
	               WHEN 'П' THEN COALESCE(datf.credit_amount, 0) - COALESCE(datf.debet_amount, 0)
	           	   ELSE 0	
	           END,
	           COALESCE(dabf.balance_out_rub, 0) + 
	           CASE mad.char_type
	               WHEN 'А' THEN COALESCE(datf.debet_amount_rub, 0) - COALESCE(datf.credit_amount_rub, 0)
	               WHEN 'П' THEN COALESCE(datf.credit_amount_rub, 0) - COALESCE(datf.debet_amount_rub, 0)
	               ELSE 0
	           END
    	FROM ds.md_account_d mad LEFT JOIN dm.dm_account_balance_f dabf 
    						 	 ON mad.account_rk = dabf.account_rk 
        					 	 AND dabf.on_date = $1 - INTERVAL '1 day'
    						 	 LEFT JOIN dm.dm_account_turnover_f datf 
    						 	 ON mad.account_rk = datf.account_rk 
        					 	 AND datf.on_date = $1
   		WHERE $1 BETWEEN mad.data_actual_date AND mad.data_actual_end_date;
	
   	proc_end := now();
	
	INSERT INTO logs.logs_table (log_start_time, log_end_time, log_message, log_err_code, log_err_msg)
    VALUES (proc_start, proc_end, msg, null, null);

	EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS 
            err_msg := message_text,
            err_code := returned_sqlstate;
        
	    INSERT INTO logs.logs_table (log_start_time, log_end_time, log_message, log_err_code, log_err_msg)
	    VALUES (proc_start, proc_end, msg, err_code, err_msg);
END;
$$
LANGUAGE plpgsql;


SELECT * FROM dm.dm_account_balance_f ORDER BY on_date, account_rk ;
SELECT * FROM logs.logs_table;
-- TRUNCATE dm.dm_account_balance_f;
-- CALL ds.fill_account_balance_f('2018-01-01'::date);
