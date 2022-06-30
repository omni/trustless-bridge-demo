FROM golang:1.18.3 as build

WORKDIR /app

COPY . .

RUN mkdir out && \
    mkdir out/light_client && \
    go build -o ./out/light_client ./cmd/light_client/... && \
    mkdir out/light_client_chain && \
    go build -o ./out/light_client_chain ./cmd/light_client_chain/... && \
    mkdir out/amb && \
    go build -o ./out/amb ./cmd/amb/...

FROM ubuntu:20.04

WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates && update-ca-certificates

COPY --from=build /app/out/ ./

EXPOSE 3333

ENTRYPOINT ["./light_client/worker"]
