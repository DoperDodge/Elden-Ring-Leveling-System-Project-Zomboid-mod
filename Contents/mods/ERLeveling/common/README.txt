This folder is intentionally almost empty.

Build 42 expects a mod to contain both a "common" folder and a version folder
("42"). The common folder is where content shared across game versions would go;
this mod keeps all of its content in the version folders instead, so nothing
lives here.

The folder still has to exist, and git does not track empty directories, which is
the only reason this file is here. Do not delete it - without it the folder will
not survive a clone or a copy, and Build 42 can fail to list the mod at all.
