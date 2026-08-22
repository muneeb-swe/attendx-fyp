from django.db import models
from django.contrib.auth.models import AbstractUser
from django.db.models import Q


class User(AbstractUser):
    ROLES = (
        ('student', 'Student'),
        ('teacher', 'Teacher'),
        ('admin', 'Admin'),
    )
    role = models.CharField(max_length=10, choices=ROLES)
    phone = models.CharField(max_length=15, blank=True)

    def __str__(self):
        return f"{self.username} ({self.role})"


class Student(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    roll_number = models.CharField(max_length=20, unique=True)
    department = models.CharField(max_length=100)
    batch = models.CharField(max_length=10)

    def __str__(self):
        return self.roll_number


class Teacher(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    department = models.CharField(max_length=100)
    employee_id = models.CharField(max_length=20, unique=True)

    def __str__(self):
        return self.user.get_full_name()


class Device(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='devices')
    public_key = models.TextField()
    device_fingerprint = models.CharField(max_length=255)
    registered_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            # One active device per student
            models.UniqueConstraint(
                fields=['student'],
                condition=Q(is_active=True),
                name='one_active_device_per_student'
            ),

            # One active student per physical device
            models.UniqueConstraint(
                fields=['device_fingerprint'],
                condition=Q(is_active=True),
                name='one_active_device_fingerprint'
            ),
        ]

    def __str__(self):
        return f"{self.student.roll_number} - {self.device_fingerprint[:20]}"


class DeviceEvent(models.Model):
    EVENT_TYPES = (
        ('enrolled', 'Enrolled (first device)'),
        ('re_enrolled', 'Re-enrolled (same physical device)'),
        ('deactivated', 'Deactivated by admin'),
        ('reactivated', 'Reactivated by admin'),
        ('mismatch_student_has_device', 'Blocked: student already has a different active device'),
        ('mismatch_fingerprint_taken', 'Blocked: this device fingerprint already belongs to another student'),
    )

    student = models.ForeignKey(
        Student, on_delete=models.CASCADE, related_name='device_events'
    )
    device = models.ForeignKey(
        Device, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='events'
    )
    event_type = models.CharField(max_length=40, choices=EVENT_TYPES)
    device_fingerprint = models.CharField(max_length=255, blank=True)
    performed_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='device_actions_performed'
    )
    conflicting_student = models.ForeignKey(
        Student, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='device_conflicts_against'
    )
    notes = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.get_event_type_display()} — {self.student.roll_number} ({self.created_at:%Y-%m-%d %H:%M})"
