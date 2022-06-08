FROM golang:1.17.8 as build

WORKDIR /app

COPY . .

RUN mkdir out && go build -o ./out ./cmd/...

FROM ubuntu:20.04

WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates && update-ca-certificates

COPY --from=build /app/out/ ./

EXPOSE 3333

RUN mkdir ./cache

ENTRYPOINT ["./worker"]
