# Sourcehut API Reference

This document provides context and references for working with Sourcehut's APIs.

## Official Documentation

The official Sourcehut API documentation can be found at:
- **https://man.sr.ht** - Contains links to API reference pages for all *.sr.ht services

## Services and Their APIs

### git.sr.ht (Git Repositories)
- **GraphQL API**: https://git.sr.ht/graphql
- **REST API**: https://git.sr.ht/api
- **Scope required**: `REPOSITORIES:RO` (read-only), `REPOSITORIES:RW` (read-write)

### todo.sr.ht (Ticket Tracking)
- **GraphQL API**: https://todo.sr.ht/graphql
- **REST API**: https://todo.sr.ht/api
- **Scope required**: `TICKETS:RO` (read-only), `TICKETS:RW` (read-write)

### hg.sr.ht (Mercurial Repositories)
- **GraphQL API**: https://hg.sr.ht/graphql
- **REST API**: https://hg.sr.ht/api
- **Scope required**: `REPOSITORIES:RO` (read-only), `REPOSITORIES:RW` (read-write)

### lists.sr.ht (Mailing Lists)
- **GraphQL API**: https://lists.sr.ht/graphql
- **REST API**: https://lists.sr.ht/api
- **Scope required**: `LISTS:RO` (read-only), `LISTS:RW` (read-write)

### builds.sr.ht (CI/CD)
- **GraphQL API**: https://builds.sr.ht/graphql
- **REST API**: https://builds.sr.ht/api
- **Scope required**: `BUILDS:RO` (read-only), `BUILDS:RW` (read-write)

### meta.sr.ht (User Accounts)
- **GraphQL API**: https://meta.sr.ht/graphql
- **REST API**: https://meta.sr.ht/api
- **Scope required**: `ACCOUNT:RO` (read-only), `ACCOUNT:RW` (read-write)

## Authentication

All API requests require a **Personal Access Token** with the appropriate scopes.

- **Token creation**: https://meta.sr.ht/oauth2/personal-token
- **Token format**: `Bearer <your-token>` in the Authorization header

## GraphQL Conventions

### Common Types

```graphql
# Cursor-based pagination
type Query {
  items(cursor: Cursor, filter: Filter): ItemsPage
}

type ItemsPage {
  results: [Item!]!
  cursor: Cursor
}

# Filter structure (varies by service)
input Filter {
  search: String
  # ... other service-specific filters
}
```

### Error Handling

Sourcehut APIs return GraphQL errors in the following format:

```json
{
  "data": null,
  "errors": [
    {
      "message": "Error message",
      "path": ["query", "field"],
      "extensions": {
        "code": "ERROR_CODE"
      }
    }
  ]
}
```

## Rate Limiting

- **Rate limits**: Vary by service and authentication status
- **Headers**: Check `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **Unauthenticated**: Lower limits (typically 60 requests/hour)
- **Authenticated**: Higher limits (typically 5000 requests/hour)

## Development Notes

### API Exploration

Use GraphiQL interfaces available at each service's `/graphql` endpoint to:
- Explore the schema
- Test queries
- Understand available fields and types

### Common Issues

1. **Filtering**: Some services may not support all filter operations. Check the schema.
2. **Pagination**: Always handle `cursor` properly for pagination.
3. **Caching**: Sourcehut APIs may have aggressive caching. Use cache headers appropriately.

### Example Query Structure

```graphql
query {
  repositories(cursor: $cursor, filter: $filter) {
    results {
      id
      name
      description
      # ... other fields
    }
    cursor
  }
}

# Variables
{
  "filter": {
    "search": "query string"
  }
}
```

## Troubleshooting

1. **401 Unauthorized**: Check token scopes and expiration
2. **403 Forbidden**: Verify you have access to the requested resource
3. **429 Too Many Requests**: Implement proper rate limiting in your client
4. **500 Internal Server Error**: Check if the API is temporarily down

## Additional Resources

- Sourcehut API Status: https://status.sr.ht
- Sourcehut Meta (announcements): https://meta.sr.ht
- Sourcehut GitHub Mirror: https://github.com/sourcehut
- IRC: #sourcehut on Libera.Chat