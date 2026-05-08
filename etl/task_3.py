import psycopg2

from config.config import load_config


def fill_f101_round_f_for_jan_2018():

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(f"""
                CALL dm.fill_f101_round_f('2018-02-01')
            """)


fill_f101_round_f_for_jan_2018()
