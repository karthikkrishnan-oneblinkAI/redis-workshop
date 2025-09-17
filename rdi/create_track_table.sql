CREATE TABLE "Track" (
	"TrackId" integer PRIMARY KEY,
	"Name" character varying(255) NOT NULL,
	"AlbumId" integer NOT NULL,
	"MediaTypeId" integer NOT NULL,
	"GenreId" integer NOT NULL,
	"Composer" character varying(255) NOT NULL,
	"Milliseconds" integer NOT NULL,
	"Bytes" integer NOT NULL,
	"UnitPrice" numeric(10,2) NOT NULL
);

/*
Putting this insert as generate_load gives an error when there are no records in
the file
*/
INSERT INTO "Track" VALUES (1,'Init Track',1,1,1,'Fela Kuti',1000,1000,19.99)
