# One image for every RelNusa process; the first argument picks the role.
FROM golang:1.26-alpine AS build
WORKDIR /src
ENV CGO_ENABLED=0 GOFLAGS=-mod=mod
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/relnusa ./cmd/relnusa

FROM alpine:3.22
RUN adduser -D -u 10001 app
COPY --from=build /out/relnusa /usr/local/bin/relnusa
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/relnusa"]
