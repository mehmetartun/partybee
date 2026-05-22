import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'N/A';
    final displayName = user?.displayName ?? email.split('@')[0];
    final photoUrl = user?.photoURL;
    final isGoogleUser =
        user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: PremiumTheme.backgroundGradient,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header / Welcome
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Profile',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage your credentials',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.redAccent,
                        size: 28,
                      ),
                      onPressed: _signOut,
                      tooltip: 'Sign Out',
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // User Profile Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        // Avatar Circle
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: PremiumTheme.primary.withValues(
                                alpha: 0.5,
                              ),
                              width: 2,
                            ),
                            image: photoUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(photoUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: photoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 36,
                                  color: PremiumTheme.textSecondary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // User Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: PremiumTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: PremiumTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    isGoogleUser
                                        ? Icons.g_mobiledata_rounded
                                        : Icons.mail_outline_rounded,
                                    size: 16,
                                    color: PremiumTheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isGoogleUser
                                        ? 'Google Sign-In'
                                        : 'Email Verified',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: PremiumTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Sign Out Button Card
                Container(
                  decoration: PremiumTheme.primaryButtonGradient,
                  child: ElevatedButton(
                    onPressed: _signOut,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                    ),
                    child: const Text('Sign Out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
