#!/bin/sh

systemctl start mariadb

echo CREATE\ DATABASE\ matura\; | mysql
echo CREATE\ USER\ matura\@localhost\; | mysql
echo GRANT\ ALL\ PRIVILEGES\ ON\ matura\.\*\ TO\ matura\@localhost\; | mysql
