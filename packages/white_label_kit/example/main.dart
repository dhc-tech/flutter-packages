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

  final config = WhiteLabelConfig.parse(sampleYaml);
  final defaultTenant = config.tenants[config.defaultTenant]!;

  print('Loaded Tenant: ${defaultTenant.name}');
  print('Application ID: ${defaultTenant.android.applicationId}');
  print('Primary Color: ${defaultTenant.theme.primaryColor}');
  print('API Base URL: ${defaultTenant.environment.apiBaseUrl}');

  // Example 2: Creating runtime metadata from configuration
  final runtime = WhiteLabelRuntime.fromConfig(defaultTenant);

  print('\nRuntime Tenant ID: ${runtime.tenantId}');
  print('Runtime Name: ${runtime.tenantName}');
  print(
    'Push Notifications: ${runtime.features["enable_push_notifications"] ?? false}',
  );
}
