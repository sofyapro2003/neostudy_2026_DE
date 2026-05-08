CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f (
	from_date DATE,
	to_date DATE,
	chapter CHAR(1),
	ledger_account CHAR(5),
	characteristic CHAR(1),
	balance_in_rub NUMERIC(23,8),
	balance_in_val NUMERIC(23,8),
	balance_in_total NUMERIC(23,8),
	turn_deb_rub NUMERIC(23,8),
	turn_deb_val NUMERIC(23,8),
	turn_deb_total NUMERIC(23,8),
	turn_cre_rub NUMERIC(23,8),
	turn_cre_val NUMERIC(23,8),
	turn_cre_total NUMERIC(23,8),
	balance_out_rub  NUMERIC(23,8),
	balance_out_val NUMERIC(23,8),
	balance_out_total NUMERIC(23,8)
);


CREATE OR REPLACE PROCEDURE dm.fill_f101_round_f(i_OnDate DATE)
AS $$
DECLARE
	i_from_date DATE; -- 
	i_to_date DATE; --
	i_chapter CHAR(1);
	i_ledger_account CHAR(5); --
	i_characteristic CHAR(1); --
	i_balance_in_rub NUMERIC(23,8);
	i_balance_in_val NUMERIC(23,8);
	i_balance_in_total NUMERIC(23,8);
	i_turn_deb_rub NUMERIC(23,8);
	i_turn_deb_val NUMERIC(23,8);
	i_turn_deb_total NUMERIC(23,8);
	i_turn_cre_rub NUMERIC(23,8);
	i_turn_cre_val NUMERIC(23,8);
	i_turn_cre_total NUMERIC(23,8);
	i_balance_out_rub  NUMERIC(23,8);
	i_balance_out_val NUMERIC(23,8);
	i_balance_out_total NUMERIC(23,8);
	
	r RECORD;

	proc_start TIMESTAMPTZ;
	proc_end TIMESTAMPTZ;
	msg TEXT DEFAULT 'Расчет витрины dm.fill_f101_round_f';
	err_code TEXT;
	err_msg TEXT;
BEGIN
	
	proc_start := now();

	i_from_date := $1 -  INTERVAL '1 month';
	i_to_date := $1 - INTERVAL '1 day';
	
	DELETE FROM dm.dm_f101_round_f
	WHERE from_date = i_from_date AND to_date = i_to_date;

	FOR r IN 
		SELECT DISTINCT(LEFT(account_number, 5)) AS r_ledger_account
		FROM ds.md_account_d
		WHERE i_from_date >= data_actual_date AND i_to_date <= data_actual_end_date
	LOOP	
	
		SELECT chapter, ledger_account::TEXT, characteristic
		INTO i_chapter, i_ledger_account, i_characteristic
		FROM ds.md_ledger_account_s
		WHERE ledger_account::TEXT = r.r_ledger_account
		AND start_date <= i_from_date AND end_date >= i_to_date;
	
		RAISE NOTICE 'chapter = %, ledger_account = %, characteristic = %', i_chapter, i_ledger_account, i_characteristic;
	
		IF NOT FOUND THEN
			i_ledger_account := r.r_ledger_account;
		END IF;
	
		-- сумма остатоков в рублях за предшествующий первому дню отчетного периода для рублевых счетов
		SELECT COALESCE(SUM(dabf.balance_out_rub), 0) INTO i_balance_in_rub 
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_balance_f dabf ON mad.account_rk = dabf.account_rk
		WHERE mad.currency_code IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND dabf.on_date = i_from_date - INTERVAL '1 day';
		
		-- сумма остатков в рублях за предшедствующий первому дню отчетного периода для всех счетов кроме рублевых
		SELECT COALESCE(SUM(dabf.balance_out_rub), 0) INTO i_balance_in_val
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_balance_f dabf ON mad.account_rk = dabf.account_rk
		WHERE mad.currency_code NOT IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND dabf.on_date = i_from_date - INTERVAL '1 day';
		
		-- сумма остатков в рублях за предшествующий первому дню отчетного периода для всех счетов
		i_balance_in_total := i_balance_in_rub + i_balance_in_val;
	
		-- сумма дебетовых и кредитовых оборотов в рублях для рублевых счетов
		SELECT COALESCE(SUM(datf.debet_amount_rub), 0),
			   COALESCE(SUM(datf.credit_amount_rub), 0)
		INTO i_turn_deb_rub, i_turn_cre_rub
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_turnover_f datf ON mad.account_rk = datf.account_rk
		WHERE mad.currency_code IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND datf.on_date BETWEEN i_from_date AND i_to_date;
	
		-- сумма дебетовых и кредитовых оборотов в рублях для всех счетов кроме рублевых
		SELECT COALESCE(SUM(datf.debet_amount_rub), 0),
			   COALESCE(SUM(datf.credit_amount_rub), 0)
		INTO i_turn_deb_val, i_turn_cre_val
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_turnover_f datf ON mad.account_rk = datf.account_rk
		WHERE mad.currency_code NOT IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND datf.on_date BETWEEN i_from_date AND i_to_date;
	
		-- сумма дебетовых оборотов в рублях для всех счетов
		i_turn_deb_total := i_turn_deb_rub + i_turn_deb_val;
	
		-- сумма кредитовых оборотов в рублях для всех счетов
		i_turn_cre_total := i_turn_cre_rub + i_turn_cre_val;
	
		-- сумма остатоков в рублях за последний день отчетного периода для рублевых счетов
		SELECT COALESCE(SUM(dabf.balance_out_rub), 0) INTO i_balance_out_rub
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_balance_f dabf ON mad.account_rk = dabf.account_rk
		WHERE mad.currency_code IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND dabf.on_date = i_to_date; 
		
		-- сумма остатков в рублях за последний день отчетного периода для всех счетов кроме рублевых
		SELECT COALESCE(SUM(dabf.balance_out_rub), 0) INTO i_balance_out_val
		FROM ds.md_account_d mad LEFT JOIN dm.dm_account_balance_f dabf ON mad.account_rk = dabf.account_rk
		WHERE mad.currency_code NOT IN ('810', '643')
		AND LEFT(mad.account_number, 5) = r.r_ledger_account
		AND dabf.on_date = i_from_date;
		
		-- сумма остатков в рублях за последний день отчетного периода для всех счетов
		i_balance_out_total := i_balance_out_rub + i_balance_out_val;
		
		PERFORM 1 FROM dm.dm_f101_round_f WHERE i_ledger_account = ledger_account;
		IF NOT FOUND THEN
			INSERT INTO dm.dm_f101_round_f(from_date, to_date, chapter, ledger_account, characteristic, 
										   balance_in_rub, balance_in_val, balance_in_total,
										   turn_deb_rub, turn_deb_val, turn_deb_total,
										   turn_cre_rub, turn_cre_val, turn_cre_total,
										   balance_out_rub, balance_out_val, balance_out_total)						   
			VALUES (i_from_date, i_to_date, i_chapter, i_ledger_account, i_characteristic, 
				    i_balance_in_rub, i_balance_in_val, i_balance_in_total,
			    i_turn_deb_rub, i_turn_deb_val, i_turn_deb_total,
			    i_turn_cre_rub, i_turn_cre_val, i_turn_cre_total,
			    i_balance_out_rub, i_balance_out_val, i_balance_out_total);
		END IF;
	END LOOP;
	
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

CALL dm.fill_f101_round_f('2018-02-01');
SELECT * FROM dm.dm_f101_round_f;
SELECT * FROM logs.logs_table;
-- TRUNCATE dm.dm_f101_round_f;
