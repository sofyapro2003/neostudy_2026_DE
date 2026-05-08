import psycopg2
import pandas as pd
import os
import chardet

from psycopg2.extras import execute_values
from config.config import load_config
from logs.logs import log_load_data, log_err_load_data


def extract_data():

    dfs = dict()
    for file in os.listdir('../files'):
        if file.endswith('.csv'):
            path = '../files/' + file

            # определение кодировки (md_currency_d - ansi, остальные - utf8)
            with open(path, 'rb') as f:
                result = chardet.detect(f.read())
                encoding = result['encoding']
            if encoding == 'TIS-620':
                encoding = 'ansi'

            table_name = file.replace('.csv', '')
            dfs[table_name] = pd.read_csv(path, sep=';', header=0, encoding=encoding)

    return dfs


def transform_data():

    dfs = extract_data()
    for key in dfs.keys():
        dfs[key] = dfs[key].drop_duplicates()
        dfs[key] = dfs[key].where(pd.notnull(dfs[key]), None)

        if key == 'md_currency_d':
            dfs[key]['CURRENCY_CODE'] = dfs[key]['CURRENCY_CODE'].apply(
                lambda x: f"{int(float(x)):03d}" if pd.notnull(x) and x != '' else '000'
            )

        for column in dfs[key].columns:
            if 'date' in column.lower():
                try:
                    dfs[key][column] = pd.to_datetime(dfs[key][column], dayfirst=True, format='mixed')
                except Exception as e:
                    dfs[key][column] = pd.NaT
                try:
                    dfs[key][column] = pd.to_datetime(dfs[key][column], dayfirst=False, format='mixed')
                except Exception as e:
                    dfs[key][column] = pd.NaT
    return dfs


def load_data_into_ft_balance_f(df, cur):

    data = [(r.ON_DATE, r.ACCOUNT_RK, r.CURRENCY_RK, r.BALANCE_OUT)
            for r in df.itertuples()]
    try:
        execute_values(cur, """
                INSERT INTO ds.ft_balance_f(on_date, account_rk, currency_rk, balance_out)
                VALUES %s
                ON CONFLICT (on_date, account_rk) 
                DO UPDATE SET 
                    currency_rk = EXCLUDED.currency_rk,
                    balance_out = EXCLUDED.balance_out
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу ft_balance_f')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу ft_balance_f', e.pgcode, str(e))


def load_data_into_ft_posting_f(df, cur):

    data = [(r.OPER_DATE, r.CREDIT_ACCOUNT_RK, r.DEBET_ACCOUNT_RK, r.CREDIT_AMOUNT, r.DEBET_AMOUNT)
            for r in df.itertuples()]
    try:
        cur.execute("""
                        DELETE FROM ds.ft_posting_f
                    """)
        execute_values(cur, """
                INSERT INTO ds.ft_posting_f(oper_date, credit_account_rk, debet_account_rk, credit_amount, debet_amount)
                VALUES %s
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу ft_posting_f')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу ft_posting_f', e.pgcode, str(e))


def load_data_into_md_account_d(df, cur):

    data = [(r.DATA_ACTUAL_DATE, r.DATA_ACTUAL_END_DATE, r.ACCOUNT_RK, r.ACCOUNT_NUMBER,
             r.CHAR_TYPE, r.CURRENCY_RK, r.CURRENCY_CODE)
            for r in df.itertuples()]
    try:
        execute_values(cur, """
                INSERT INTO ds.md_account_d(data_actual_date, data_actual_end_date, account_rk, account_number,
                                            char_type, currency_rk, currency_code)
                VALUES %s
                ON CONFLICT (data_actual_date, account_rk) 
                DO UPDATE SET 
                    data_actual_end_date = EXCLUDED.data_actual_end_date,
                    account_number = EXCLUDED.account_number,
                    char_type = EXCLUDED.char_type,
                    currency_rk = EXCLUDED.currency_rk,
                    currency_code = EXCLUDED.currency_code
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу md_account_d')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу md_account_d', e.pgcode, str(e))


def load_data_into_md_currency_d(df, cur):

    data = [(r.CURRENCY_RK, r.DATA_ACTUAL_DATE, r.DATA_ACTUAL_END_DATE, r.CURRENCY_CODE, r.CODE_ISO_CHAR)
            for r in df.itertuples()]
    try:
        execute_values(cur, """
                INSERT INTO ds.md_currency_d(currency_rk, data_actual_date, data_actual_end_date, 
                                             currency_code, code_iso_char)
                VALUES %s
                ON CONFLICT (currency_rk, data_actual_date) 
                DO UPDATE SET 
                    data_actual_end_date = EXCLUDED.data_actual_end_date,
                    currency_code = EXCLUDED.currency_code,
                    code_iso_char = EXCLUDED.code_iso_char
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу md_currency_d')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу md_currency_d', e.pgcode, str(e))


def load_data_into_md_exchange_rate_d(df, cur):

    data = [(r.DATA_ACTUAL_DATE, r.DATA_ACTUAL_END_DATE, r.CURRENCY_RK, r.REDUCED_COURCE, r.CODE_ISO_NUM)
            for r in df.itertuples()]
    try:
        execute_values(cur, """
                INSERT INTO ds.md_exchange_rate_d(data_actual_date, data_actual_end_date, currency_rk,
                                                  reduced_cource, code_iso_num)
                VALUES %s
                ON CONFLICT (data_actual_date, currency_rk) 
                DO UPDATE SET 
                    data_actual_end_date = EXCLUDED.data_actual_end_date,
                    reduced_cource = EXCLUDED.reduced_cource,
                    code_iso_num = EXCLUDED.code_iso_num
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу md_exchange_rate_d')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу md_exchange_rate_d', e.pgcode, str(e))


def load_data_into_md_ledger_account_s(df, cur):

    data = [(r.CHAPTER, r.CHAPTER_NAME, r.SECTION_NUMBER, r.SECTION_NAME, r.SUBSECTION_NAME,
             r.LEDGER1_ACCOUNT, r.LEDGER1_ACCOUNT_NAME, r.LEDGER_ACCOUNT, r.LEDGER_ACCOUNT_NAME,
             r.CHARACTERISTIC, r.START_DATE, r.END_DATE)
            for r in df.itertuples()]
    try:
        execute_values(cur, """
                INSERT INTO ds.md_ledger_account_s(chapter, chapter_name, section_number, section_name, subsection_name,
                                                   ledger1_account, ledger1_account_name, ledger_account, 
                                                   ledger_account_name, characteristic, start_date, end_date)
                VALUES %s
                ON CONFLICT (ledger_account, start_date) 
                DO UPDATE SET 
                    chapter = EXCLUDED.chapter,
                    chapter_name = EXCLUDED.chapter_name,
                    section_number = EXCLUDED.section_number,
                    section_name = EXCLUDED.section_name,
                    subsection_name = EXCLUDED.subsection_name,
                    ledger1_account = EXCLUDED.ledger1_account,
                    ledger1_account_name = EXCLUDED.ledger1_account_name,
                    ledger_account_name = EXCLUDED.ledger_account_name,
                    characteristic = EXCLUDED.characteristic,
                    end_date = EXCLUDED.end_date
            """, data)
        log_load_data(cur, 'Загрузка данных в таблицу md_ledger_account_s')
    except psycopg2.Error as e:
        log_err_load_data(cur, 'Загрузка данных в таблицу md_ledger_account_s', e.pgcode, str(e))


def load_data():

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            dfs = transform_data()
            load_data_into_ft_balance_f(dfs['ft_balance_f'], cur)
            load_data_into_ft_posting_f(dfs['ft_posting_f'], cur)
            load_data_into_md_account_d(dfs['md_account_d'], cur)
            load_data_into_md_currency_d(dfs['md_currency_d'], cur)
            load_data_into_md_exchange_rate_d(dfs['md_exchange_rate_d'], cur)
            load_data_into_md_ledger_account_s(dfs['md_ledger_account_s'], cur)


load_data()
