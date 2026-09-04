(function (root) {
  function inviteCode() {
    var params = new URLSearchParams(root.location.search);
    var fromQuery = params.get("table") || params.get("code");
    if (fromQuery) {
      return fromQuery.trim().toUpperCase();
    }

    var parts = root.location.pathname.replace(/\/+$/, "").split("/").filter(Boolean);
    if (parts[0] && parts[0].toLowerCase() === "table" && parts[1]) {
      return parts[1].toUpperCase();
    }

    return "";
  }

  function appUrl(code) {
    return "com.mathisgad.pokerleader://table/" + encodeURIComponent(code);
  }

  function openApp() {
    var code = inviteCode();
    if (!code) {
      return "";
    }
    root.location.href = appUrl(code);
    return code;
  }

  root.PotMasterTableInvite = {
    inviteCode: inviteCode,
    appUrl: appUrl,
    openApp: openApp,
  };
})(window);
