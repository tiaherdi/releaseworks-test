using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// No-op when started from the console; lets the same build run as a Windows Service.
builder.Services.AddWindowsService();

var app = builder.Build();

var version = Assembly.GetExecutingAssembly()
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "unknown";

app.MapGet("/", () => "SampleApi is running");
app.MapGet("/health", () => Results.Ok(new { status = "Healthy", version }));

app.Run();

public partial class Program;
