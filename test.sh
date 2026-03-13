#!/usr/bin/env bash

for i in $(sqlite3 kavita.db "SELECT DISTINCT tbl_name FROM sqlite_master WHERE sql like '%LibraryId%'"); do
	echo $i;
	#sqlite3 kavita.db "select * from $i;"
	sqlite3 kavita.db "delete from $i where LibraryId = 2 or LibraryId = 3;"
done;
