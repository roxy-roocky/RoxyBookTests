using System;
using Microsoft.JSInterop;

namespace RoxyBookTests.Helpers;

public class LocalStorage
{
    public LocalStorage(IJSRuntime jsRuntime)
    {
        _jsRuntime = jsRuntime;
    }

    protected IJSRuntime _jsRuntime {get; set; }

    public async Task SetItem(string key, string value)
    {
        await _jsRuntime.InvokeVoidAsync("localStorage.setItem", key, value);
    }

    public async Task<string> GetItem(string key)
    {
        return await _jsRuntime.InvokeAsync<string>("localStorage.getItem", key);
    }

    public async Task<string> RemoveItem(string key)
    {
        return await _jsRuntime.InvokeAsync<string>("localStorage.removeItem", key);
    }
}
