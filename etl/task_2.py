import psycopg2

from config.config import load_config


def fill_account_turnover_f_for_jan_2018():

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            for i in range(1, 32):
                cur.execute(f"""
                    CALL ds.fill_account_turnover_f('2018-01-{i:02d}')
                """)


#fill_account_turnover_f_for_jan_2018()


def fill_account_balance_f_for_jan_2018():

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            for i in range(1, 32):
                cur.execute(f"""
                    CALL ds.fill_account_balance_f('2018-01-{i:02d}')
                """)


fill_account_balance_f_for_jan_2018()
