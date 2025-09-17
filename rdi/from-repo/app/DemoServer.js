const express = require("express");

const redis = require("redis");
const client = redis.createClient({
  url: `redis://${process.env.REDIS_TARGET_DB_HOST || "redis"}:${
    process.env.REDIS_TARGET_DB_PORT || 12000
  }`
});

const app = express();
app.set("view engine", "ejs");
app.use(express.static("public"));

app.use(async (req, res, next) => {
  next();
});

app.get("/", (req, res) => {
  res.sendFile("index.html");
});

app.get("/search", async (req, res, next) => {
  // Create an index...
  try {
    // Documentation: https://oss.redis.com/redisearch/Commands/#ftcreate
    await client.ft.create(
      "idx:Tracks",
      {
        TrackId: redis.SchemaFieldTypes.NUMERIC,
        Name: {
          type: redis.SchemaFieldTypes.TEXT,
          sortable: true
        },
        AlbumId: redis.SchemaFieldTypes.NUMERIC,

        Composer: {
          type: redis.SchemaFieldTypes.TEXT,
          sortable: true
        },
        GenreId: redis.SchemaFieldTypes.NUMERIC,
        MediaType: redis.SchemaFieldTypes.NUMERIC
      },
      {
        ON: "HASH",
        PREFIX: "track:"
      }
    );
  } catch (e) {
    if (e.message !== "Index already exists") {
      console.error(
        "Something went wrong, perhaps RediSearch isn't installed..."
      );
      // Something went wrong, perhaps RedisSearch isn't installed...
      console.error(e);
      process.exit(1);
    }
  }

  // Perform a search query, find all the docs... sort by age, descending.
  // Documentation: https://oss.redis.com/redisearch/Commands/#ftsearch
  // Query synatax: https://oss.redis.com/redisearch/Query_Syntax/
  const genreId = req.query.genreId;

  try {
    const results = await client.ft.search(
      "idx:Tracks",
      `@GenreId:[${genreId} ${genreId}]`,
      {
        LIMIT: {
          from: 1,
          size: 10
        },
        SORTBY: {
          BY: "TrackId",
          DIRECTION: "DESC" // or 'ASC' (default if DIRECTION is not present)
        }
      }
    );

    res.setHeader("Content-Type", "application/json");
    const genres = ["Folk", "Rock", "Jazz", "Soul", "Blues"];
    results.documents.forEach((element) => {
      element.value["GenreId"] = genres[element.value["GenreId"]];
    });
    res.end(JSON.stringify(results));
  } catch (e) {
    console.error(e);
    res.end(JSON.stringify({ error: true }));
  }
});

// Start REST server
const server = app.listen(parseInt(process.env.APP_PORT) || 8081, () => {
  client.connect().then();
  const host = server.address().address;
  const port = server.address().port;
  console.log("REST API listening on http://%s:%s", host, port);
});
