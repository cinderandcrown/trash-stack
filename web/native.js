var __defProp = Object.defineProperty;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __esm = (fn, res) => function __init() {
  return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
};
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};

// node_modules/@capacitor/core/dist/index.js
var ExceptionCode, CapacitorException, getPlatformId, createCapacitor, initCapacitorGlobal, Capacitor, registerPlugin, WebPlugin, encode, decode, CapacitorCookiesPluginWeb, CapacitorCookies, readBlobAsBase64, normalizeHttpHeaders, buildUrlParams, buildRequestInit, CapacitorHttpPluginWeb, CapacitorHttp, SystemBarsStyle, SystemBarType, SystemBarsPluginWeb, SystemBars;
var init_dist = __esm({
  "node_modules/@capacitor/core/dist/index.js"() {
    (function(ExceptionCode2) {
      ExceptionCode2["Unimplemented"] = "UNIMPLEMENTED";
      ExceptionCode2["Unavailable"] = "UNAVAILABLE";
    })(ExceptionCode || (ExceptionCode = {}));
    CapacitorException = class extends Error {
      constructor(message, code, data) {
        super(message);
        this.message = message;
        this.code = code;
        this.data = data;
      }
    };
    getPlatformId = (win) => {
      var _a, _b;
      if (win === null || win === void 0 ? void 0 : win.androidBridge) {
        return "android";
      } else if ((_b = (_a = win === null || win === void 0 ? void 0 : win.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.bridge) {
        return "ios";
      } else {
        return "web";
      }
    };
    createCapacitor = (win) => {
      const capCustomPlatform = win.CapacitorCustomPlatform || null;
      const cap = win.Capacitor || {};
      const Plugins = cap.Plugins = cap.Plugins || {};
      const getPlatform = () => {
        return capCustomPlatform !== null ? capCustomPlatform.name : getPlatformId(win);
      };
      const isNativePlatform = () => getPlatform() !== "web";
      const isPluginAvailable = (pluginName) => {
        const plugin = registeredPlugins.get(pluginName);
        if (plugin === null || plugin === void 0 ? void 0 : plugin.platforms.has(getPlatform())) {
          return true;
        }
        if (getPluginHeader(pluginName)) {
          return true;
        }
        return false;
      };
      const getPluginHeader = (pluginName) => {
        var _a;
        return (_a = cap.PluginHeaders) === null || _a === void 0 ? void 0 : _a.find((h) => h.name === pluginName);
      };
      const handleError = (err) => win.console.error(err);
      const registeredPlugins = /* @__PURE__ */ new Map();
      const registerPlugin2 = (pluginName, jsImplementations = {}) => {
        const registeredPlugin = registeredPlugins.get(pluginName);
        if (registeredPlugin) {
          console.warn(`Capacitor plugin "${pluginName}" already registered. Cannot register plugins twice.`);
          return registeredPlugin.proxy;
        }
        const platform2 = getPlatform();
        const pluginHeader = getPluginHeader(pluginName);
        let jsImplementation;
        const loadPluginImplementation = async () => {
          if (!jsImplementation && platform2 in jsImplementations) {
            jsImplementation = typeof jsImplementations[platform2] === "function" ? jsImplementation = await jsImplementations[platform2]() : jsImplementation = jsImplementations[platform2];
          } else if (capCustomPlatform !== null && !jsImplementation && "web" in jsImplementations) {
            jsImplementation = typeof jsImplementations["web"] === "function" ? jsImplementation = await jsImplementations["web"]() : jsImplementation = jsImplementations["web"];
          }
          return jsImplementation;
        };
        const createPluginMethod = (impl, prop) => {
          var _a, _b;
          if (pluginHeader) {
            const methodHeader = pluginHeader === null || pluginHeader === void 0 ? void 0 : pluginHeader.methods.find((m) => prop === m.name);
            if (methodHeader) {
              if (methodHeader.rtype === "promise") {
                return (options) => cap.nativePromise(pluginName, prop.toString(), options);
              } else {
                return (options, callback) => cap.nativeCallback(pluginName, prop.toString(), options, callback);
              }
            } else if (impl) {
              return (_a = impl[prop]) === null || _a === void 0 ? void 0 : _a.bind(impl);
            }
          } else if (impl) {
            return (_b = impl[prop]) === null || _b === void 0 ? void 0 : _b.bind(impl);
          } else {
            throw new CapacitorException(`"${pluginName}" plugin is not implemented on ${platform2}`, ExceptionCode.Unimplemented);
          }
        };
        const createPluginMethodWrapper = (prop) => {
          let remove;
          const wrapper = (...args) => {
            const p = loadPluginImplementation().then((impl) => {
              const fn = createPluginMethod(impl, prop);
              if (fn) {
                const p2 = fn(...args);
                remove = p2 === null || p2 === void 0 ? void 0 : p2.remove;
                return p2;
              } else {
                throw new CapacitorException(`"${pluginName}.${prop}()" is not implemented on ${platform2}`, ExceptionCode.Unimplemented);
              }
            });
            if (prop === "addListener") {
              p.remove = async () => remove();
            }
            return p;
          };
          wrapper.toString = () => `${prop.toString()}() { [capacitor code] }`;
          Object.defineProperty(wrapper, "name", {
            value: prop,
            writable: false,
            configurable: false
          });
          return wrapper;
        };
        const addListener = createPluginMethodWrapper("addListener");
        const removeListener = createPluginMethodWrapper("removeListener");
        const addListenerNative = (eventName, callback) => {
          const call = addListener({ eventName }, callback).then((callbackId) => callbackId);
          const remove = async () => {
            const callbackId = await call;
            await removeListener({
              eventName,
              callbackId
            });
          };
          const p = new Promise((resolve) => call.then(() => resolve({ remove })));
          p.remove = async () => {
            console.warn(`Using addListener() without 'await' is deprecated.`);
            await remove();
          };
          return p;
        };
        const proxy = new Proxy({}, {
          get(_, prop) {
            switch (prop) {
              // https://github.com/facebook/react/issues/20030
              case "$$typeof":
                return void 0;
              case "toJSON":
                return () => ({});
              case "addListener":
                return pluginHeader ? addListenerNative : addListener;
              case "removeListener":
                return removeListener;
              default:
                return createPluginMethodWrapper(prop);
            }
          }
        });
        Plugins[pluginName] = proxy;
        registeredPlugins.set(pluginName, {
          name: pluginName,
          proxy,
          platforms: /* @__PURE__ */ new Set([...Object.keys(jsImplementations), ...pluginHeader ? [platform2] : []])
        });
        return proxy;
      };
      if (!cap.convertFileSrc) {
        cap.convertFileSrc = (filePath) => filePath;
      }
      cap.getPlatform = getPlatform;
      cap.handleError = handleError;
      cap.isNativePlatform = isNativePlatform;
      cap.isPluginAvailable = isPluginAvailable;
      cap.registerPlugin = registerPlugin2;
      cap.Exception = CapacitorException;
      cap.DEBUG = !!cap.DEBUG;
      cap.isLoggingEnabled = !!cap.isLoggingEnabled;
      return cap;
    };
    initCapacitorGlobal = (win) => win.Capacitor = createCapacitor(win);
    Capacitor = /* @__PURE__ */ initCapacitorGlobal(typeof globalThis !== "undefined" ? globalThis : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : typeof global !== "undefined" ? global : {});
    registerPlugin = Capacitor.registerPlugin;
    WebPlugin = class {
      constructor() {
        this.listeners = {};
        this.retainedEventArguments = {};
        this.windowListeners = {};
      }
      addListener(eventName, listenerFunc) {
        let firstListener = false;
        const listeners = this.listeners[eventName];
        if (!listeners) {
          this.listeners[eventName] = [];
          firstListener = true;
        }
        this.listeners[eventName].push(listenerFunc);
        const windowListener = this.windowListeners[eventName];
        if (windowListener && !windowListener.registered) {
          this.addWindowListener(windowListener);
        }
        if (firstListener) {
          this.sendRetainedArgumentsForEvent(eventName);
        }
        const remove = async () => this.removeListener(eventName, listenerFunc);
        const p = Promise.resolve({ remove });
        return p;
      }
      async removeAllListeners() {
        this.listeners = {};
        for (const listener in this.windowListeners) {
          this.removeWindowListener(this.windowListeners[listener]);
        }
        this.windowListeners = {};
      }
      notifyListeners(eventName, data, retainUntilConsumed) {
        const listeners = this.listeners[eventName];
        if (!listeners) {
          if (retainUntilConsumed) {
            let args = this.retainedEventArguments[eventName];
            if (!args) {
              args = [];
            }
            args.push(data);
            this.retainedEventArguments[eventName] = args;
          }
          return;
        }
        listeners.forEach((listener) => listener(data));
      }
      hasListeners(eventName) {
        var _a;
        return !!((_a = this.listeners[eventName]) === null || _a === void 0 ? void 0 : _a.length);
      }
      registerWindowListener(windowEventName, pluginEventName) {
        this.windowListeners[pluginEventName] = {
          registered: false,
          windowEventName,
          pluginEventName,
          handler: (event) => {
            this.notifyListeners(pluginEventName, event);
          }
        };
      }
      unimplemented(msg = "not implemented") {
        return new Capacitor.Exception(msg, ExceptionCode.Unimplemented);
      }
      unavailable(msg = "not available") {
        return new Capacitor.Exception(msg, ExceptionCode.Unavailable);
      }
      async removeListener(eventName, listenerFunc) {
        const listeners = this.listeners[eventName];
        if (!listeners) {
          return;
        }
        const index = listeners.indexOf(listenerFunc);
        if (index !== -1) {
          this.listeners[eventName].splice(index, 1);
        }
        if (!this.listeners[eventName].length) {
          this.removeWindowListener(this.windowListeners[eventName]);
        }
      }
      addWindowListener(handle) {
        window.addEventListener(handle.windowEventName, handle.handler);
        handle.registered = true;
      }
      removeWindowListener(handle) {
        if (!handle) {
          return;
        }
        window.removeEventListener(handle.windowEventName, handle.handler);
        handle.registered = false;
      }
      sendRetainedArgumentsForEvent(eventName) {
        const args = this.retainedEventArguments[eventName];
        if (!args) {
          return;
        }
        delete this.retainedEventArguments[eventName];
        args.forEach((arg) => {
          this.notifyListeners(eventName, arg);
        });
      }
    };
    encode = (str) => encodeURIComponent(str).replace(/%(2[346B]|5E|60|7C)/g, decodeURIComponent).replace(/[()]/g, escape);
    decode = (str) => str.replace(/(%[\dA-F]{2})+/gi, decodeURIComponent);
    CapacitorCookiesPluginWeb = class extends WebPlugin {
      async getCookies() {
        const cookies = document.cookie;
        const cookieMap = {};
        cookies.split(";").forEach((cookie) => {
          if (cookie.length <= 0)
            return;
          let [key2, value] = cookie.replace(/=/, "CAP_COOKIE").split("CAP_COOKIE");
          key2 = decode(key2).trim();
          value = decode(value).trim();
          cookieMap[key2] = value;
        });
        return cookieMap;
      }
      async setCookie(options) {
        try {
          const encodedKey = encode(options.key);
          const encodedValue = encode(options.value);
          const expires = options.expires ? `; expires=${options.expires.replace("expires=", "")}` : "";
          const path = (options.path || "/").replace("path=", "");
          const domain = options.url != null && options.url.length > 0 ? `domain=${options.url}` : "";
          document.cookie = `${encodedKey}=${encodedValue || ""}${expires}; path=${path}; ${domain};`;
        } catch (error) {
          return Promise.reject(error);
        }
      }
      async deleteCookie(options) {
        try {
          document.cookie = `${options.key}=; Max-Age=0`;
        } catch (error) {
          return Promise.reject(error);
        }
      }
      async clearCookies() {
        try {
          const cookies = document.cookie.split(";") || [];
          for (const cookie of cookies) {
            document.cookie = cookie.replace(/^ +/, "").replace(/=.*/, `=;expires=${(/* @__PURE__ */ new Date()).toUTCString()};path=/`);
          }
        } catch (error) {
          return Promise.reject(error);
        }
      }
      async clearAllCookies() {
        try {
          await this.clearCookies();
        } catch (error) {
          return Promise.reject(error);
        }
      }
    };
    CapacitorCookies = registerPlugin("CapacitorCookies", {
      web: () => new CapacitorCookiesPluginWeb()
    });
    readBlobAsBase64 = async (blob) => new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const base64String = reader.result;
        resolve(base64String.indexOf(",") >= 0 ? base64String.split(",")[1] : base64String);
      };
      reader.onerror = (error) => reject(error);
      reader.readAsDataURL(blob);
    });
    normalizeHttpHeaders = (headers = {}) => {
      const originalKeys = Object.keys(headers);
      const loweredKeys = Object.keys(headers).map((k) => k.toLocaleLowerCase());
      const normalized = loweredKeys.reduce((acc, key2, index) => {
        acc[key2] = headers[originalKeys[index]];
        return acc;
      }, {});
      return normalized;
    };
    buildUrlParams = (params, shouldEncode = true) => {
      if (!params)
        return null;
      const output = Object.entries(params).reduce((accumulator, entry) => {
        const [key2, value] = entry;
        let encodedValue;
        let item;
        if (Array.isArray(value)) {
          item = "";
          value.forEach((str) => {
            encodedValue = shouldEncode ? encodeURIComponent(str) : str;
            item += `${key2}=${encodedValue}&`;
          });
          item.slice(0, -1);
        } else {
          encodedValue = shouldEncode ? encodeURIComponent(value) : value;
          item = `${key2}=${encodedValue}`;
        }
        return `${accumulator}&${item}`;
      }, "");
      return output.substr(1);
    };
    buildRequestInit = (options, extra = {}) => {
      const output = Object.assign({ method: options.method || "GET", headers: options.headers }, extra);
      const headers = normalizeHttpHeaders(options.headers);
      const type = headers["content-type"] || "";
      if (typeof options.data === "string") {
        output.body = options.data;
      } else if (type.includes("application/x-www-form-urlencoded")) {
        const params = new URLSearchParams();
        for (const [key2, value] of Object.entries(options.data || {})) {
          params.set(key2, value);
        }
        output.body = params.toString();
      } else if (type.includes("multipart/form-data") || options.data instanceof FormData) {
        const form = new FormData();
        if (options.data instanceof FormData) {
          options.data.forEach((value, key2) => {
            form.append(key2, value);
          });
        } else {
          for (const key2 of Object.keys(options.data)) {
            form.append(key2, options.data[key2]);
          }
        }
        output.body = form;
        const headers2 = new Headers(output.headers);
        headers2.delete("content-type");
        output.headers = headers2;
      } else if (type.includes("application/json") || typeof options.data === "object") {
        output.body = JSON.stringify(options.data);
      }
      return output;
    };
    CapacitorHttpPluginWeb = class extends WebPlugin {
      /**
       * Perform an Http request given a set of options
       * @param options Options to build the HTTP request
       */
      async request(options) {
        const requestInit = buildRequestInit(options, options.webFetchExtra);
        const urlParams = buildUrlParams(options.params, options.shouldEncodeUrlParams);
        const url = urlParams ? `${options.url}?${urlParams}` : options.url;
        const response = await fetch(url, requestInit);
        const contentType = response.headers.get("content-type") || "";
        let { responseType = "text" } = response.ok ? options : {};
        if (contentType.includes("application/json")) {
          responseType = "json";
        }
        let data;
        let blob;
        switch (responseType) {
          case "arraybuffer":
          case "blob":
            blob = await response.blob();
            data = await readBlobAsBase64(blob);
            break;
          case "json":
            data = await response.json();
            break;
          case "document":
          case "text":
          default:
            data = await response.text();
        }
        const headers = {};
        response.headers.forEach((value, key2) => {
          headers[key2] = value;
        });
        return {
          data,
          headers,
          status: response.status,
          url: response.url
        };
      }
      /**
       * Perform an Http GET request given a set of options
       * @param options Options to build the HTTP request
       */
      async get(options) {
        return this.request(Object.assign(Object.assign({}, options), { method: "GET" }));
      }
      /**
       * Perform an Http POST request given a set of options
       * @param options Options to build the HTTP request
       */
      async post(options) {
        return this.request(Object.assign(Object.assign({}, options), { method: "POST" }));
      }
      /**
       * Perform an Http PUT request given a set of options
       * @param options Options to build the HTTP request
       */
      async put(options) {
        return this.request(Object.assign(Object.assign({}, options), { method: "PUT" }));
      }
      /**
       * Perform an Http PATCH request given a set of options
       * @param options Options to build the HTTP request
       */
      async patch(options) {
        return this.request(Object.assign(Object.assign({}, options), { method: "PATCH" }));
      }
      /**
       * Perform an Http DELETE request given a set of options
       * @param options Options to build the HTTP request
       */
      async delete(options) {
        return this.request(Object.assign(Object.assign({}, options), { method: "DELETE" }));
      }
    };
    CapacitorHttp = registerPlugin("CapacitorHttp", {
      web: () => new CapacitorHttpPluginWeb()
    });
    (function(SystemBarsStyle2) {
      SystemBarsStyle2["Dark"] = "DARK";
      SystemBarsStyle2["Light"] = "LIGHT";
      SystemBarsStyle2["Default"] = "DEFAULT";
    })(SystemBarsStyle || (SystemBarsStyle = {}));
    (function(SystemBarType2) {
      SystemBarType2["StatusBar"] = "StatusBar";
      SystemBarType2["NavigationBar"] = "NavigationBar";
    })(SystemBarType || (SystemBarType = {}));
    SystemBarsPluginWeb = class extends WebPlugin {
      async setStyle() {
        this.unavailable("not available for web");
      }
      async setAnimation() {
        this.unavailable("not available for web");
      }
      async show() {
        this.unavailable("not available for web");
      }
      async hide() {
        this.unavailable("not available for web");
      }
    };
    SystemBars = registerPlugin("SystemBars", {
      web: () => new SystemBarsPluginWeb()
    });
  }
});

// node_modules/@capacitor/haptics/dist/esm/definitions.js
var ImpactStyle, NotificationType;
var init_definitions = __esm({
  "node_modules/@capacitor/haptics/dist/esm/definitions.js"() {
    (function(ImpactStyle2) {
      ImpactStyle2["Heavy"] = "HEAVY";
      ImpactStyle2["Medium"] = "MEDIUM";
      ImpactStyle2["Light"] = "LIGHT";
    })(ImpactStyle || (ImpactStyle = {}));
    (function(NotificationType2) {
      NotificationType2["Success"] = "SUCCESS";
      NotificationType2["Warning"] = "WARNING";
      NotificationType2["Error"] = "ERROR";
    })(NotificationType || (NotificationType = {}));
  }
});

// node_modules/@capacitor/haptics/dist/esm/web.js
var web_exports = {};
__export(web_exports, {
  HapticsWeb: () => HapticsWeb
});
var HapticsWeb;
var init_web = __esm({
  "node_modules/@capacitor/haptics/dist/esm/web.js"() {
    init_dist();
    init_definitions();
    HapticsWeb = class extends WebPlugin {
      constructor() {
        super(...arguments);
        this.selectionStarted = false;
      }
      async impact(options) {
        const pattern = this.patternForImpact(options === null || options === void 0 ? void 0 : options.style);
        this.vibrateWithPattern(pattern);
      }
      async notification(options) {
        const pattern = this.patternForNotification(options === null || options === void 0 ? void 0 : options.type);
        this.vibrateWithPattern(pattern);
      }
      async vibrate(options) {
        const duration = (options === null || options === void 0 ? void 0 : options.duration) || 300;
        this.vibrateWithPattern([duration]);
      }
      async selectionStart() {
        this.selectionStarted = true;
      }
      async selectionChanged() {
        if (this.selectionStarted) {
          this.vibrateWithPattern([70]);
        }
      }
      async selectionEnd() {
        this.selectionStarted = false;
      }
      patternForImpact(style = ImpactStyle.Heavy) {
        if (style === ImpactStyle.Medium) {
          return [43];
        } else if (style === ImpactStyle.Light) {
          return [20];
        }
        return [61];
      }
      patternForNotification(type = NotificationType.Success) {
        if (type === NotificationType.Warning) {
          return [30, 40, 30, 50, 60];
        } else if (type === NotificationType.Error) {
          return [27, 45, 50];
        }
        return [35, 65, 21];
      }
      vibrateWithPattern(pattern) {
        if (navigator.vibrate) {
          navigator.vibrate(pattern);
        } else {
          throw this.unavailable("Browser does not support the vibrate API");
        }
      }
    };
  }
});

// node_modules/@capacitor/preferences/dist/esm/web.js
var web_exports2 = {};
__export(web_exports2, {
  PreferencesWeb: () => PreferencesWeb
});
var PreferencesWeb;
var init_web2 = __esm({
  "node_modules/@capacitor/preferences/dist/esm/web.js"() {
    init_dist();
    PreferencesWeb = class extends WebPlugin {
      constructor() {
        super(...arguments);
        this.group = "CapacitorStorage";
      }
      async configure({ group }) {
        if (typeof group === "string") {
          this.group = group;
        }
      }
      async get(options) {
        const value = this.impl.getItem(this.applyPrefix(options.key));
        return { value };
      }
      async set(options) {
        this.impl.setItem(this.applyPrefix(options.key), options.value);
      }
      async remove(options) {
        this.impl.removeItem(this.applyPrefix(options.key));
      }
      async keys() {
        const keys = this.rawKeys().map((k) => k.substring(this.prefix.length));
        return { keys };
      }
      async clear() {
        for (const key2 of this.rawKeys()) {
          this.impl.removeItem(key2);
        }
      }
      async migrate() {
        var _a;
        const migrated = [];
        const existing = [];
        const oldprefix = "_cap_";
        const keys = Object.keys(this.impl).filter((k) => k.indexOf(oldprefix) === 0);
        for (const oldkey of keys) {
          const key2 = oldkey.substring(oldprefix.length);
          const value = (_a = this.impl.getItem(oldkey)) !== null && _a !== void 0 ? _a : "";
          const { value: currentValue } = await this.get({ key: key2 });
          if (typeof currentValue === "string") {
            existing.push(key2);
          } else {
            await this.set({ key: key2, value });
            migrated.push(key2);
          }
        }
        return { migrated, existing };
      }
      async removeOld() {
        const oldprefix = "_cap_";
        const keys = Object.keys(this.impl).filter((k) => k.indexOf(oldprefix) === 0);
        for (const oldkey of keys) {
          this.impl.removeItem(oldkey);
        }
      }
      get impl() {
        return window.localStorage;
      }
      get prefix() {
        return this.group === "NativeStorage" ? "" : `${this.group}.`;
      }
      rawKeys() {
        return Object.keys(this.impl).filter((k) => k.indexOf(this.prefix) === 0);
      }
      applyPrefix(key2) {
        return this.prefix + key2;
      }
    };
  }
});

// node_modules/@capacitor/splash-screen/dist/esm/web.js
var web_exports3 = {};
__export(web_exports3, {
  SplashScreenWeb: () => SplashScreenWeb
});
var SplashScreenWeb;
var init_web3 = __esm({
  "node_modules/@capacitor/splash-screen/dist/esm/web.js"() {
    init_dist();
    SplashScreenWeb = class extends WebPlugin {
      async show(_options) {
        return void 0;
      }
      async hide(_options) {
        return void 0;
      }
    };
  }
});

// node_modules/@capacitor/app/dist/esm/web.js
var web_exports4 = {};
__export(web_exports4, {
  AppWeb: () => AppWeb
});
var AppWeb;
var init_web4 = __esm({
  "node_modules/@capacitor/app/dist/esm/web.js"() {
    init_dist();
    AppWeb = class extends WebPlugin {
      constructor() {
        super();
        this.handleVisibilityChange = () => {
          const data = {
            isActive: document.hidden !== true
          };
          this.notifyListeners("appStateChange", data);
          if (document.hidden) {
            this.notifyListeners("pause", null);
          } else {
            this.notifyListeners("resume", null);
          }
        };
        document.addEventListener("visibilitychange", this.handleVisibilityChange, false);
      }
      exitApp() {
        throw this.unimplemented("Not implemented on web.");
      }
      async getInfo() {
        throw this.unimplemented("Not implemented on web.");
      }
      async getLaunchUrl() {
        return { url: "" };
      }
      async getState() {
        return { isActive: document.hidden !== true };
      }
      async minimizeApp() {
        throw this.unimplemented("Not implemented on web.");
      }
      async toggleBackButtonHandler() {
        throw this.unimplemented("Not implemented on web.");
      }
      async getAppLanguage() {
        return {
          value: navigator.language.split("-")[0].toLowerCase()
        };
      }
    };
  }
});

// node_modules/@capacitor-community/admob/dist/esm/consent/consent-status.enum.js
var AdmobConsentStatus;
var init_consent_status_enum = __esm({
  "node_modules/@capacitor-community/admob/dist/esm/consent/consent-status.enum.js"() {
    (function(AdmobConsentStatus2) {
      AdmobConsentStatus2["NOT_REQUIRED"] = "NOT_REQUIRED";
      AdmobConsentStatus2["OBTAINED"] = "OBTAINED";
      AdmobConsentStatus2["REQUIRED"] = "REQUIRED";
      AdmobConsentStatus2["UNKNOWN"] = "UNKNOWN";
    })(AdmobConsentStatus || (AdmobConsentStatus = {}));
  }
});

// node_modules/@capacitor-community/admob/dist/esm/consent/privacy-options-requirement-status.enum.js
var PrivacyOptionsRequirementStatus;
var init_privacy_options_requirement_status_enum = __esm({
  "node_modules/@capacitor-community/admob/dist/esm/consent/privacy-options-requirement-status.enum.js"() {
    (function(PrivacyOptionsRequirementStatus2) {
      PrivacyOptionsRequirementStatus2["NOT_REQUIRED"] = "NOT_REQUIRED";
      PrivacyOptionsRequirementStatus2["REQUIRED"] = "REQUIRED";
      PrivacyOptionsRequirementStatus2["UNKNOWN"] = "UNKNOWN";
    })(PrivacyOptionsRequirementStatus || (PrivacyOptionsRequirementStatus = {}));
  }
});

// node_modules/@capacitor-community/admob/dist/esm/web.js
var web_exports5 = {};
__export(web_exports5, {
  AdMobWeb: () => AdMobWeb
});
var AdMobWeb;
var init_web5 = __esm({
  "node_modules/@capacitor-community/admob/dist/esm/web.js"() {
    init_dist();
    init_consent_status_enum();
    init_privacy_options_requirement_status_enum();
    AdMobWeb = class extends WebPlugin {
      async initialize() {
        console.log("initialize");
      }
      async requestTrackingAuthorization() {
        console.log("requestTrackingAuthorization");
      }
      async trackingAuthorizationStatus() {
        return {
          status: "authorized"
        };
      }
      async requestConsentInfo(options) {
        console.log("requestConsentInfo", options);
        return {
          status: AdmobConsentStatus.REQUIRED,
          isConsentFormAvailable: true,
          canRequestAds: true,
          privacyOptionsRequirementStatus: PrivacyOptionsRequirementStatus.REQUIRED
        };
      }
      async showPrivacyOptionsForm() {
        console.log("showPrivacyOptionsForm");
      }
      async showConsentForm() {
        console.log("showConsentForm");
        return {
          status: AdmobConsentStatus.REQUIRED,
          canRequestAds: true,
          privacyOptionsRequirementStatus: PrivacyOptionsRequirementStatus.REQUIRED
        };
      }
      async resetConsentInfo() {
        console.log("resetConsentInfo");
      }
      async setApplicationMuted(options) {
        console.log("setApplicationMuted", options);
      }
      async setApplicationVolume(options) {
        console.log("setApplicationVolume", options);
      }
      async showBanner(options) {
        console.log("showBanner", options);
      }
      async hideBanner() {
        console.log("hideBanner");
      }
      async resumeBanner() {
        console.log("resumeBanner");
      }
      async removeBanner() {
        console.log("removeBanner");
      }
      async startNativeAdFeed() {
        throw new Error("Native ads are only available on iOS and Android");
      }
      async destroyNativeAdFeed(options) {
        console.log("destroyNativeAdFeed", options);
      }
      async loadNativeAd() {
        throw new Error("Native ads are only available on iOS and Android");
      }
      async updateNativeAdPlacements(options) {
        console.log("updateNativeAdPlacements", options);
      }
      async removeNativeAd(options) {
        console.log("removeNativeAd", options);
      }
      async prepareInterstitial(options) {
        console.log("prepareInterstitial", options);
        return {
          adUnitId: options.adId
        };
      }
      async showInterstitial(options) {
        console.log("showInterstitial", options);
      }
      async prepareRewardVideoAd(options) {
        console.log("prepareRewardVideoAd", options);
        return {
          adUnitId: options.adId
        };
      }
      async showRewardVideoAd(options) {
        console.log("showRewardVideoAd", options);
        return {
          type: "",
          amount: 0
        };
      }
      async prepareRewardInterstitialAd(options) {
        console.log("prepareRewardInterstitialAd", options);
        return {
          adUnitId: options.adId
        };
      }
      async showRewardInterstitialAd(options) {
        console.log("showRewardInterstitialAd", options);
        return {
          type: "",
          amount: 0
        };
      }
      async loadAppOpen(options) {
        console.log("loadAppOpen", options);
        return {
          adUnitId: options.adId
        };
      }
      async showAppOpen(options) {
        console.log("showAppOpen", options);
      }
      async isAppOpenLoaded() {
        return { value: false };
      }
      addListener(eventName, listenerFunc) {
        void listenerFunc;
        console.log("addListener", eventName);
        return Promise.resolve({ remove: () => Promise.resolve() });
      }
    };
  }
});

// src/native-bridge.js
init_dist();

// node_modules/@capacitor/haptics/dist/esm/index.js
init_dist();
init_definitions();
var Haptics = registerPlugin("Haptics", {
  web: () => Promise.resolve().then(() => (init_web(), web_exports)).then((m) => new m.HapticsWeb())
});

// node_modules/@capacitor/preferences/dist/esm/index.js
init_dist();
var Preferences = registerPlugin("Preferences", {
  web: () => Promise.resolve().then(() => (init_web2(), web_exports2)).then((m) => new m.PreferencesWeb())
});

// node_modules/@capacitor/status-bar/dist/esm/index.js
init_dist();

// node_modules/@capacitor/status-bar/dist/esm/definitions.js
var Style;
(function(Style2) {
  Style2["Dark"] = "DARK";
  Style2["Light"] = "LIGHT";
  Style2["Default"] = "DEFAULT";
})(Style || (Style = {}));
var Animation;
(function(Animation2) {
  Animation2["None"] = "NONE";
  Animation2["Slide"] = "SLIDE";
  Animation2["Fade"] = "FADE";
})(Animation || (Animation = {}));

// node_modules/@capacitor/status-bar/dist/esm/index.js
var StatusBar = registerPlugin("StatusBar");

// node_modules/@capacitor/splash-screen/dist/esm/index.js
init_dist();
var SplashScreen = registerPlugin("SplashScreen", {
  web: () => Promise.resolve().then(() => (init_web3(), web_exports3)).then((m) => new m.SplashScreenWeb())
});

// node_modules/@capacitor/app/dist/esm/index.js
init_dist();
var App = registerPlugin("App", {
  web: () => Promise.resolve().then(() => (init_web4(), web_exports4)).then((m) => new m.AppWeb())
});

// src/ads.js
init_dist();

// node_modules/@capacitor-community/admob/dist/esm/index.js
init_dist();

// node_modules/@capacitor-community/admob/dist/esm/native-ads/native-ad-feed.js
init_dist();

// node_modules/@webview-native-ui/engine/dist/projection/styles.js
var hidden = ":is([data-native-ui-snapshot-source], [data-native-ui-snapshot-prepared], [data-native-ui-snapshot-content])";
var snapshotStyles = `
@layer native-ui-projection {
${hidden}, ${hidden} *, ${hidden}::part(native) { visibility: hidden !important; }
${hidden}::before, ${hidden}::after,
${hidden} *::before, ${hidden} *::after {
  visibility: hidden !important;
}
}
[data-native-ui-snapshot-visible] { opacity:1!important;overflow:visible!important; }
[data-native-ui-snapshot-visible][data-native-ui-snapshot-positioned] { position:relative!important; }
`;

// node_modules/@webview-native-ui/engine/dist/dom/overlays.js
var key = Symbol.for("@webview-native-ui/engine/overlays/v1");

// node_modules/@webview-native-ui/engine/dist/projection/placement.js
var placementKey = Symbol.for("webview-native-ui-engine.projection-placement");

// node_modules/@capacitor-community/admob/dist/esm/native-ads/native-ad-template.enum.js
var NativeAdTemplate;
(function(NativeAdTemplate2) {
  NativeAdTemplate2["Small"] = "small";
  NativeAdTemplate2["Medium"] = "medium";
})(NativeAdTemplate || (NativeAdTemplate = {}));

// node_modules/@capacitor-community/admob/dist/esm/native-ads/native-ad-feed.js
var bridge;
var configureNativeAdBridge = (adMobBridge) => {
  bridge = adMobBridge;
};

// node_modules/@capacitor-community/admob/dist/esm/definitions.js
var MaxAdContentRating;
(function(MaxAdContentRating2) {
  MaxAdContentRating2["General"] = "General";
  MaxAdContentRating2["ParentalGuidance"] = "ParentalGuidance";
  MaxAdContentRating2["Teen"] = "Teen";
  MaxAdContentRating2["MatureAudience"] = "MatureAudience";
})(MaxAdContentRating || (MaxAdContentRating = {}));

// node_modules/@capacitor-community/admob/dist/esm/banner/banner-ad-plugin-events.enum.js
var BannerAdPluginEvents;
(function(BannerAdPluginEvents2) {
  BannerAdPluginEvents2["SizeChanged"] = "bannerAdSizeChanged";
  BannerAdPluginEvents2["Loaded"] = "bannerAdLoaded";
  BannerAdPluginEvents2["FailedToLoad"] = "bannerAdFailedToLoad";
  BannerAdPluginEvents2["Opened"] = "bannerAdOpened";
  BannerAdPluginEvents2["Closed"] = "bannerAdClosed";
  BannerAdPluginEvents2["AdImpression"] = "bannerAdImpression";
  BannerAdPluginEvents2["AdPaid"] = "bannerAdPaid";
})(BannerAdPluginEvents || (BannerAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/banner/banner-ad-position.enum.js
var BannerAdPosition;
(function(BannerAdPosition2) {
  BannerAdPosition2["TOP_CENTER"] = "TOP_CENTER";
  BannerAdPosition2["CENTER"] = "CENTER";
  BannerAdPosition2["BOTTOM_CENTER"] = "BOTTOM_CENTER";
})(BannerAdPosition || (BannerAdPosition = {}));

// node_modules/@capacitor-community/admob/dist/esm/banner/banner-ad-size.enum.js
var BannerAdSize;
(function(BannerAdSize2) {
  BannerAdSize2["BANNER"] = "BANNER";
  BannerAdSize2["FULL_BANNER"] = "FULL_BANNER";
  BannerAdSize2["LARGE_BANNER"] = "LARGE_BANNER";
  BannerAdSize2["MEDIUM_RECTANGLE"] = "MEDIUM_RECTANGLE";
  BannerAdSize2["LEADERBOARD"] = "LEADERBOARD";
  BannerAdSize2["ADAPTIVE_BANNER"] = "ADAPTIVE_BANNER";
  BannerAdSize2["SMART_BANNER"] = "SMART_BANNER";
})(BannerAdSize || (BannerAdSize = {}));

// node_modules/@capacitor-community/admob/dist/esm/interstitial/interstitial-ad-plugin-events.enum.js
var InterstitialAdPluginEvents;
(function(InterstitialAdPluginEvents2) {
  InterstitialAdPluginEvents2["Loaded"] = "interstitialAdLoaded";
  InterstitialAdPluginEvents2["FailedToLoad"] = "interstitialAdFailedToLoad";
  InterstitialAdPluginEvents2["Showed"] = "interstitialAdShowed";
  InterstitialAdPluginEvents2["FailedToShow"] = "interstitialAdFailedToShow";
  InterstitialAdPluginEvents2["Dismissed"] = "interstitialAdDismissed";
  InterstitialAdPluginEvents2["AdImpression"] = "interstitialAdImpression";
})(InterstitialAdPluginEvents || (InterstitialAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/reward-interstitial/reward-interstitial-ad-plugin-events.enum.js
var RewardInterstitialAdPluginEvents;
(function(RewardInterstitialAdPluginEvents2) {
  RewardInterstitialAdPluginEvents2["Loaded"] = "onRewardedInterstitialAdLoaded";
  RewardInterstitialAdPluginEvents2["FailedToLoad"] = "onRewardedInterstitialAdFailedToLoad";
  RewardInterstitialAdPluginEvents2["Showed"] = "onRewardedInterstitialAdShowed";
  RewardInterstitialAdPluginEvents2["FailedToShow"] = "onRewardedInterstitialAdFailedToShow";
  RewardInterstitialAdPluginEvents2["Dismissed"] = "onRewardedInterstitialAdDismissed";
  RewardInterstitialAdPluginEvents2["Rewarded"] = "onRewardedInterstitialAdReward";
  RewardInterstitialAdPluginEvents2["AdImpression"] = "onRewardedInterstitialAdImpression";
})(RewardInterstitialAdPluginEvents || (RewardInterstitialAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/reward/reward-ad-plugin-events.enum.js
var RewardAdPluginEvents;
(function(RewardAdPluginEvents2) {
  RewardAdPluginEvents2["adClicked"] = "onRewardedVideoAdClicked";
  RewardAdPluginEvents2["Loaded"] = "onRewardedVideoAdLoaded";
  RewardAdPluginEvents2["FailedToLoad"] = "onRewardedVideoAdFailedToLoad";
  RewardAdPluginEvents2["Showed"] = "onRewardedVideoAdShowed";
  RewardAdPluginEvents2["FailedToShow"] = "onRewardedVideoAdFailedToShow";
  RewardAdPluginEvents2["Dismissed"] = "onRewardedVideoAdDismissed";
  RewardAdPluginEvents2["Rewarded"] = "onRewardedVideoAdReward";
  RewardAdPluginEvents2["AdImpression"] = "onRewardedVideoAdImpression";
})(RewardAdPluginEvents || (RewardAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/consent/index.js
init_consent_status_enum();

// node_modules/@capacitor-community/admob/dist/esm/consent/consent-debug-geography.enum.js
var AdmobConsentDebugGeography;
(function(AdmobConsentDebugGeography2) {
  AdmobConsentDebugGeography2[AdmobConsentDebugGeography2["DISABLED"] = 0] = "DISABLED";
  AdmobConsentDebugGeography2[AdmobConsentDebugGeography2["EEA"] = 1] = "EEA";
  AdmobConsentDebugGeography2[AdmobConsentDebugGeography2["NOT_EEA"] = 2] = "NOT_EEA";
  AdmobConsentDebugGeography2[AdmobConsentDebugGeography2["US"] = 3] = "US";
  AdmobConsentDebugGeography2[AdmobConsentDebugGeography2["OTHER"] = 4] = "OTHER";
})(AdmobConsentDebugGeography || (AdmobConsentDebugGeography = {}));

// node_modules/@capacitor-community/admob/dist/esm/shared/ad-mob-revenue-data.interface.js
var AdValuePrecision;
(function(AdValuePrecision2) {
  AdValuePrecision2[AdValuePrecision2["Unknown"] = 0] = "Unknown";
  AdValuePrecision2[AdValuePrecision2["Estimated"] = 1] = "Estimated";
  AdValuePrecision2[AdValuePrecision2["PublisherProvided"] = 2] = "PublisherProvided";
  AdValuePrecision2[AdValuePrecision2["Precise"] = 3] = "Precise";
})(AdValuePrecision || (AdValuePrecision = {}));

// node_modules/@capacitor-community/admob/dist/esm/app-open/app-open-ad-plugin-events.enum.js
var AppOpenAdPluginEvents;
(function(AppOpenAdPluginEvents2) {
  AppOpenAdPluginEvents2["Loaded"] = "appOpenAdLoaded";
  AppOpenAdPluginEvents2["FailedToLoad"] = "appOpenAdFailedToLoad";
  AppOpenAdPluginEvents2["Opened"] = "appOpenAdOpened";
  AppOpenAdPluginEvents2["Closed"] = "appOpenAdClosed";
  AppOpenAdPluginEvents2["FailedToShow"] = "appOpenAdFailedToShow";
  AppOpenAdPluginEvents2["AdImpression"] = "appOpenAdImpression";
})(AppOpenAdPluginEvents || (AppOpenAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/native-ads/native-ad-plugin-events.enum.js
var NativeAdPluginEvents;
(function(NativeAdPluginEvents2) {
  NativeAdPluginEvents2["Loaded"] = "nativeAdLoaded";
  NativeAdPluginEvents2["FailedToLoad"] = "nativeAdFailedToLoad";
  NativeAdPluginEvents2["Clicked"] = "nativeAdClicked";
  NativeAdPluginEvents2["AdImpression"] = "nativeAdImpression";
  NativeAdPluginEvents2["Opened"] = "nativeAdOpened";
  NativeAdPluginEvents2["Closed"] = "nativeAdClosed";
  NativeAdPluginEvents2["AdPaid"] = "nativeAdPaid";
})(NativeAdPluginEvents || (NativeAdPluginEvents = {}));

// node_modules/@capacitor-community/admob/dist/esm/index.js
var nativeAdBridge = registerPlugin("AdMob", {
  web: () => Promise.resolve().then(() => (init_web5(), web_exports5)).then((m) => new m.AdMobWeb())
});
var AdMob = nativeAdBridge;
configureNativeAdBridge(nativeAdBridge);

// src/ads.js
var TEST = {
  appId: {
    ios: "ca-app-pub-3940256099942544~1458002511",
    android: "ca-app-pub-3940256099942544~3347511713"
  },
  interstitial: {
    ios: "ca-app-pub-3940256099942544/4411468910",
    android: "ca-app-pub-3940256099942544/1033173712"
  },
  rewarded: {
    ios: "ca-app-pub-3940256099942544/1712485313",
    android: "ca-app-pub-3940256099942544/5224354917"
  }
};
function platform() {
  return Capacitor.getPlatform();
}
function cfg() {
  return typeof window !== "undefined" && window.TRASH_AD_CONFIG || {};
}
function unit(kind) {
  const c = cfg();
  const p = platform();
  const custom = c[kind] && (c[kind][p] || c[kind].default);
  if (custom && String(custom).trim()) return String(custom).trim();
  return TEST[kind][p] || TEST[kind].android;
}
var ready = false;
var canRequestAds = true;
var sessionRuns = 0;
var oversSinceInterstitial = 0;
var interstitialReady = false;
var rewardReady = false;
async function requestTrackingIfNeeded() {
  if (platform() !== "ios") return;
  try {
    const status = await AdMob.trackingAuthorizationStatus();
    if (status && (status.status === "notDetermined" || status.status === 0)) {
      await AdMob.requestTrackingAuthorization();
    }
  } catch (_) {
  }
}
async function runConsentFlow() {
  try {
    let info = await AdMob.requestConsentInfo({
      debugGeography: cfg().debugGeography,
      testDeviceIdentifiers: cfg().testDeviceIds || []
    });
    if (info && info.isConsentFormAvailable && info.status === AdmobConsentStatus.REQUIRED) {
      info = await AdMob.showConsentForm();
    }
    canRequestAds = !info || info.canRequestAds !== false;
  } catch (_) {
    canRequestAds = true;
  }
}
async function initAds() {
  if (!Capacitor.isNativePlatform()) {
    ready = true;
    canRequestAds = true;
    return { ready, canRequestAds, mode: "web-stub" };
  }
  await requestTrackingIfNeeded();
  await runConsentFlow();
  if (!canRequestAds) {
    ready = false;
    return { ready, canRequestAds, mode: "consent-blocked" };
  }
  try {
    await AdMob.initialize({
      initializeForTesting: cfg().useTestIds !== false,
      testingDevices: cfg().testDeviceIds || []
    });
    ready = true;
    await preloadInterstitial();
    await preloadRewarded();
  } catch (_) {
    ready = false;
  }
  return { ready, canRequestAds, mode: "native" };
}
async function preloadInterstitial() {
  if (!ready || !canRequestAds || !Capacitor.isNativePlatform()) return;
  try {
    await AdMob.prepareInterstitial({ adId: unit("interstitial") });
    interstitialReady = true;
  } catch (_) {
    interstitialReady = false;
  }
}
async function preloadRewarded() {
  if (!ready || !canRequestAds || !Capacitor.isNativePlatform()) return;
  try {
    await AdMob.prepareRewardVideoAd({ adId: unit("rewarded") });
    rewardReady = true;
  } catch (_) {
    rewardReady = false;
  }
}
function noteRunStarted() {
  sessionRuns += 1;
}
async function maybeShowInterstitial({ adsRemoved } = {}) {
  if (adsRemoved) return false;
  oversSinceInterstitial += 1;
  if (sessionRuns <= 2) return false;
  if (oversSinceInterstitial < 3) return false;
  if (!Capacitor.isNativePlatform()) {
    oversSinceInterstitial = 0;
    return false;
  }
  if (!ready || !canRequestAds) return false;
  try {
    if (!interstitialReady) await preloadInterstitial();
    if (!interstitialReady) return false;
    await AdMob.showInterstitial();
    oversSinceInterstitial = 0;
    interstitialReady = false;
    await preloadInterstitial();
    return true;
  } catch (_) {
    interstitialReady = false;
    return false;
  }
}
function showRewarded(reason) {
  return new Promise(async (resolve) => {
    if (!Capacitor.isNativePlatform()) {
      setTimeout(() => resolve(true), 600);
      return;
    }
    if (!ready || !canRequestAds) {
      resolve(false);
      return;
    }
    let settled = false;
    const finish = (ok) => {
      if (settled) return;
      settled = true;
      resolve(!!ok);
    };
    const rewardHandle = await AdMob.addListener(
      RewardAdPluginEvents.Rewarded,
      () => finish(true)
    ).catch(() => null);
    const dismissHandle = await AdMob.addListener(
      RewardAdPluginEvents.Dismissed,
      () => finish(false)
    ).catch(() => null);
    const failHandle = await AdMob.addListener(
      RewardAdPluginEvents.FailedToLoad,
      () => finish(false)
    ).catch(() => null);
    try {
      if (!rewardReady) await preloadRewarded();
      await AdMob.showRewardVideoAd();
      setTimeout(() => finish(false), 12e4);
    } catch (_) {
      finish(false);
    } finally {
      setTimeout(() => {
        rewardHandle && rewardHandle.remove && rewardHandle.remove();
        dismissHandle && dismissHandle.remove && dismissHandle.remove();
        failHandle && failHandle.remove && failHandle.remove();
        preloadRewarded();
      }, 1500);
    }
  });
}
function getAdDebugInfo() {
  return {
    ready,
    canRequestAds,
    sessionRuns,
    oversSinceInterstitial,
    platform: platform(),
    interstitialUnit: unit("interstitial"),
    rewardedUnit: unit("rewarded"),
    usingTestDefaults: !(cfg().interstitial && cfg().interstitial[platform()])
  };
}

// src/native-bridge.js
var native = Capacitor.isNativePlatform();
async function prepareChrome() {
  if (!native) return;
  try {
    await StatusBar.hide();
  } catch (_) {
  }
  try {
    await StatusBar.setStyle({ style: Style.Dark });
  } catch (_) {
  }
  try {
    await StatusBar.setOverlaysWebView({ overlay: true });
  } catch (_) {
  }
}
async function hideSplash() {
  if (!native) return;
  try {
    await SplashScreen.hide({ fadeOutDuration: 220 });
  } catch (_) {
  }
}
async function haptic(ms) {
  const duration = Array.isArray(ms) ? ms.reduce((a, b) => a + b, 0) / ms.length : ms;
  if (!native) {
    try {
      if (navigator.vibrate) navigator.vibrate(ms);
    } catch (_) {
    }
    return;
  }
  try {
    if (duration >= 80) {
      await Haptics.impact({ style: ImpactStyle.Heavy });
    } else if (duration >= 30) {
      await Haptics.impact({ style: ImpactStyle.Medium });
    } else {
      await Haptics.impact({ style: ImpactStyle.Light });
    }
  } catch (_) {
    try {
      await Haptics.notification({ type: NotificationType.Success });
    } catch (__) {
    }
  }
}
async function getPref(key2) {
  if (native) {
    const { value } = await Preferences.get({ key: key2 });
    return value;
  }
  try {
    return localStorage.getItem(key2);
  } catch (_) {
    return null;
  }
}
async function setPref(key2, value) {
  if (native) {
    await Preferences.set({ key: key2, value });
    try {
      localStorage.setItem(key2, value);
    } catch (_) {
    }
    return;
  }
  try {
    localStorage.setItem(key2, value);
  } catch (_) {
  }
}
async function loadProgress(key2) {
  let value = await getPref(key2);
  if (value == null) {
    try {
      const legacy = localStorage.getItem(key2);
      if (legacy != null) {
        value = legacy;
        if (native) {
          await Preferences.set({ key: key2, value: legacy });
        }
      }
    } catch (_) {
    }
  }
  return value;
}
async function saveProgress(key2, value) {
  await setPref(key2, value);
}
async function consumeShotMode() {
  try {
    const { value } = await Preferences.get({ key: "trashStack.shot" });
    if (value) {
      await Preferences.remove({ key: "trashStack.shot" });
      return value;
    }
  } catch (_) {
  }
  try {
    const hash = typeof location !== "undefined" && location.hash || "";
    if (hash.includes("shot=game")) return "game";
  } catch (_) {
  }
  return null;
}
window.TrashNative = {
  isNative: native,
  platform: Capacitor.getPlatform(),
  prepareChrome,
  hideSplash,
  haptic,
  loadProgress,
  saveProgress,
  consumeShotMode,
  initAds,
  noteRunStarted,
  maybeShowInterstitial,
  showRewarded,
  getAdDebugInfo,
  App
};
document.documentElement.classList.toggle("native-app", native);
document.documentElement.dataset.platform = Capacitor.getPlatform();
/*! Bundled license information:

@capacitor/core/dist/index.js:
  (*! Capacitor: https://capacitorjs.com/ - MIT License *)
*/
