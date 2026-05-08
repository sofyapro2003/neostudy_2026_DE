import time
from datetime import datetime


def log_load_data(cur, message):

    start_time = datetime.now()
    time.sleep(1)
    cur.execute("""
                INSERT INTO logs.logs_table (log_start_time, log_end_time, log_message)
                VALUES (%s, %s, %s)
            """, (start_time, datetime.now(), message))


def log_err_load_data(cur, message, err_code, err_msg):

    start_time = datetime.now()
    time.sleep(1)
    cur.execute("""
                INSERT INTO logs.logs_table 
                (log_start_time, log_end_time, log_message, log_err_code, log_err_msg)
                VALUES (%s, %s, %s, %s, %s)
            """, (start_time, datetime.now(), message, err_code, err_msg))
