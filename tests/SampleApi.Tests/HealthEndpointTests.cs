using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;

namespace SampleApi.Tests;

public class HealthEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Health_ReturnsOk()
    {
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Root_ReturnsRunningMessage()
    {
        var body = await _client.GetStringAsync("/");

        Assert.Equal("SampleApi is running", body);
    }
}
