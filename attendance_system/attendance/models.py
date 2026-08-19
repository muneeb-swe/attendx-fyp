from django.db import models
from users.models import Student, Teacher, Device


class Class(models.Model):
    name = models.CharField(max_length=100)
    subject = models.CharField(max_length=100)
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE)
    students = models.ManyToManyField(Student, through='Enrollment')

    def __str__(self):
        return f"{self.name} - {self.subject}"


class Enrollment(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE)
    class_enrolled = models.ForeignKey(Class, on_delete=models.CASCADE)
    enrolled_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('student', 'class_enrolled')


class Session(models.Model):
    class_ref = models.ForeignKey(Class, on_delete=models.CASCADE)
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE)
    qr_token = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)
    is_submitted = models.BooleanField(default=False) 
    stopped_at = models.DateTimeField(null=True, blank=True) 
    expected_count = models.IntegerField(null=True, blank=True)
    present_count = models.IntegerField(default=0)

    def __str__(self):
        return f"{self.class_ref.name} - {self.created_at}"
    

class AttendanceRecord(models.Model):
    STATUS = (
        ('present', 'Present'),
        ('absent', 'Absent'),
        ('manual', 'Manual Override'),
    )
    session = models.ForeignKey(Session, on_delete=models.CASCADE)
    student = models.ForeignKey(Student, on_delete=models.CASCADE)
    device = models.ForeignKey(Device, on_delete=models.CASCADE, null=True)
    timestamp = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=10, choices=STATUS, default='present')
    signature = models.TextField(blank=True)
    original_status = models.CharField(max_length=10, choices=STATUS, default='present')
    is_modified = models.BooleanField(default=False)

    class Meta:
        unique_together = ('session', 'student')

    def __str__(self):
        return f"{self.student.roll_number} - {self.session}"
