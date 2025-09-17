from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import User, Client
from diagrams.generic.os import LinuxGeneral
from diagrams.onprem.inmemory import Redis
from diagrams.programming.language import Nodejs
from diagrams.onprem.database import Postgresql
from diagrams.generic.database import SQL

with Diagram("Topology", show=False, direction="LR"):
    user = User("user")
    with Cluster("Cloud"):
        terminal = Client("terminal")
        redis = Redis("Redis Enterprise")
        rdi = LinuxGeneral("RDI server")
        logs = Client("logs")
        debezium = LinuxGeneral("Debezium")
        postgres =Postgresql("Postgres")
        sqlpad = SQL("SQL Pad")
        app = Nodejs("App")
        redisInsight = Client("Redis Insight")



    user >> Edge(label='browser') >> terminal >> Edge(label='ssh') >> rdi

    postgres >> debezium >> redis

    user >> Edge(label='browser') >> sqlpad >> postgres

    user >> Edge(label='browser') >> app >> redis << redisInsight

    logs >> debezium
   # user >> Edge(label='ssh') >> dind_host
