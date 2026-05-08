import psycopg2
import pandas as pd

from config.config import load_config
from logs.logs import log_load_data, log_err_load_data


def extract_data_from_table(table_name):

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(f"""
                       SELECT * FROM dm.{table_name};
                   """)
                rows = cur.fetchall()

                columns = [desc[0] for desc in cur.description]
                description = {desc[0]: desc[1] for desc in cur.description}
                df = pd.DataFrame(rows, columns=columns)

                log_load_data(cur, f'Выгрузка данных из таблицы {table_name}')
            except psycopg2.Error as e:
                log_err_load_data(cur, f'Выгрузка данных из таблицы {table_name}', e.pgcode, str(e))
    return df, description


def transform_data_for_file(df, description):

    numeric_columns = [col for col, typ in description.items()
                       if typ == 1700]
    for col in numeric_columns:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
    return df


def load_data_to_file(df, filename):

    path = '../result_files/' + filename
    df.to_csv(path, mode='w', index=False, sep=';', encoding='utf-8')

'''
df, description = extract_data_from_table('dm_f101_round_f')
df = transform_data_for_file(df, description)
load_data_to_file(df, 'dm_f101_round_f.csv')
'''

def extract_data_from_file(filename):

    path = '../result_files/' + filename
    df = pd.read_csv(path, sep=';', header=0, encoding='utf-8')
    return df


def transform_data_for_table(df):

    for column in df.columns:
        if 'date' in column:
            try:
                df[column] = pd.to_datetime(df[column], dayfirst=True, format='mixed')
            except Exception as e:
                df[column] = pd.NaT
            try:
                df[column] = pd.to_datetime(df[column], dayfirst=False, format='mixed')
            except Exception as e:
                df[column] = pd.NaT
    return df


def load_data_to_table(df, table_name):

    config = load_config()
    with psycopg2.connect(**config) as conn:
        with conn.cursor() as cur:
            try:
                columns = ', '.join(df.columns.tolist())
                for r in df:
                    data = [tuple(row) for row in df.to_numpy()]
                    placeholders = ', '.join(['%s'] * len(df.columns))

                    cur.executemany(f"""
                                        INSERT INTO dm.{table_name}({columns})
                                        VALUES ({placeholders})
                                """, data)
                log_load_data(cur, f'Загрузка данных в таблицу {table_name}')
            except psycopg2.Error as e:
                log_err_load_data(cur, f'Загрузка данных в таблицу {table_name}', e.pgcode, str(e))


df2 = extract_data_from_file('dm_f101_round_f.csv')
df2 = transform_data_for_table(df2)
load_data_to_table(df2, 'dm_f101_round_f_v2')
