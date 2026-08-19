import 'package:white_label_kit/white_label_kit.dart';

void main() {
  // Example 1: Loading and validating tenant configuration from YAML
  const sampleYaml = '''
white_label:
  default_tenant: acme
  tenants:
    acme:
      name: "Acme App"
      android:
        application_id: "com.example.acme"
      ios:
        bundle_id: "com.example.acme"
      theme:
        primary_color: "#1E88E5"
      environment:
        api_base_url: "https://api.example.com"
      features:
        enable_push_notifications: true
''';

  final WhiteLabelConfig config = WhiteLabelConfig.parse(sampleYaml);
  final TenantConfig defaultTenant = config.tenants[config.defaultTenant]!;

  // ignore: avoid_print - example CLI output
  print('Loaded Tenant: ${defaultTenant.name}');
  // ignore: avoid_print - example CLI output
  print('Application ID: ${defaultTenant.android.applicationId}');
  // ignore: avoid_print - example CLI output
  print('Primary Color: ${defaultTenant.theme.primaryColor}');
  // ignore: avoid_print - example CLI output
  print('API Base URL: ${defaultTenant.environment.apiBaseUrl}');

  // Example 2: Creating runtime metadata from configuration
  final runtime = WhiteLabelRuntime.fromConfig(defaultTenant);

  // ignore: avoid_print - example CLI output
  print('\nRuntime Tenant ID: ${runtime.tenantId}');
  // ignore: avoid_print - example CLI output
  print('Runtime Name: ${runtime.tenantName}');
  // ignore: avoid_print - example CLI output
  print('Push Notifications: ${runtime.features["enable_push_notifications"] ?? false}');
}
